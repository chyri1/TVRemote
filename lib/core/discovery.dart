import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

class DiscoveredTv {
  final String name;
  final String host;
  final String? manufacturer;
  final String? model;

  const DiscoveredTv(
    this.name,
    this.host, {
    this.manufacturer,
    this.model,
  });

  /// Nome amigável formatado (ex: "Multilaser Android TV")
  String get displayName => name;

  /// Detalhes para diferenciar múltiplos aparelhos (ex: "Expressluck • 192.168.3.16")
  String get subtitle {
    final parts = <String>[];
    if (manufacturer != null &&
        manufacturer!.isNotEmpty &&
        !name.toLowerCase().contains(manufacturer!.toLowerCase())) {
      parts.add(manufacturer!);
    }
    if (model != null &&
        model!.isNotEmpty &&
        model != name &&
        model != manufacturer &&
        !name.toLowerCase().contains(model!.toLowerCase())) {
      parts.add(model!);
    }
    parts.add(host);
    return parts.join(' • ');
  }
}

class TvMetadata {
  final String name;
  final String? manufacturer;
  final String? model;

  const TvMetadata({
    required this.name,
    this.manufacturer,
    this.model,
  });
}

/// Hybrid discovery: mDNS + Fast LAN subnet port-sweep (ports 6467/6466).
///
/// Generic Android TVs often omit mDNS advertisements or are blocked by
/// Windows firewall, so scanning port 6467 on the local subnet guarantees
/// discovery across all devices on the same Wi-Fi/Ethernet network.
class TvDiscovery {
  static const _services = [
    '_androidtvremote2._tcp.local',
    '_androidtvremote._tcp.local',
    '_googlecast._tcp.local',
  ];

  Stream<DiscoveredTv> scan({
    Duration timeout = const Duration(seconds: 5),
  }) {
    final controller = StreamController<DiscoveredTv>();
    final seen = <String>{};

    Future.wait([
      _scanMdns(controller, seen, timeout),
      _scanSubnet(controller, seen),
    ]).then((_) {
      if (!controller.isClosed) controller.close();
    }).catchError((_) {
      if (!controller.isClosed) controller.close();
    });

    return controller.stream;
  }

  Future<void> _scanMdns(
    StreamController<DiscoveredTv> controller,
    Set<String> seen,
    Duration timeout,
  ) async {
    final client = MDnsClient(
      rawDatagramSocketFactory: (host, int port,
              {bool reuseAddress = true, bool reusePort = false, int ttl = 1}) =>
          RawDatagramSocket.bind(host, port,
              reuseAddress: true, reusePort: false, ttl: ttl),
    );

    try {
      await client.start();
      for (final service in _services) {
        try {
          await for (final ptr in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(service),
            timeout: const Duration(seconds: 2),
          )) {
            await for (final srv in client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
              timeout: const Duration(milliseconds: 1500),
            )) {
              await for (final ip in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: const Duration(milliseconds: 1500),
              )) {
                final host = ip.address.address;
                if (seen.add(host)) {
                  final rawName = ptr.domainName.split('.').first;
                  final initialName = rawName.isEmpty ? 'Android TV' : rawName;
                  if (!controller.isClosed) {
                    controller.add(DiscoveredTv(initialName, host));
                  }
                  // Enriquece imediatamente com fabricante e modelo completos
                  resolveTvMetadata(host).then((meta) {
                    if (!controller.isClosed) {
                      controller.add(DiscoveredTv(
                        meta.name,
                        host,
                        manufacturer: meta.manufacturer,
                        model: meta.model,
                      ));
                    }
                  }).catchError((_) {});
                }
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      client.stop();
    }
  }

  Future<void> _scanSubnet(
    StreamController<DiscoveredTv> controller,
    Set<String> seen,
  ) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      final candidatePrefixes = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4 && addr.address != '127.0.0.1') {
            candidatePrefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
          }
        }
      }

      for (final prefix in candidatePrefixes) {
        // Scan subnet in parallel chunks
        const chunkSize = 28;
        for (var i = 1; i <= 254; i += chunkSize) {
          final end = (i + chunkSize - 1) > 254 ? 254 : (i + chunkSize - 1);
          final futures = <Future<void>>[];

          for (var hostNum = i; hostNum <= end; hostNum++) {
            final ip = '$prefix$hostNum';
            if (seen.contains(ip)) continue;

            futures.add(() async {
              try {
                bool isTv = false;
                try {
                  // Test Remote v2 Pairing port 6467
                  final s = await Socket.connect(
                    ip,
                    6467,
                    timeout: const Duration(milliseconds: 400),
                  );
                  s.done.catchError((_) {});
                  try {
                    s.destroy();
                  } catch (_) {}
                  isTv = true;
                } catch (_) {
                  // Also check port 6466
                  try {
                    final s = await Socket.connect(
                      ip,
                      6466,
                      timeout: const Duration(milliseconds: 300),
                    );
                    s.done.catchError((_) {});
                    try {
                      s.destroy();
                    } catch (_) {}
                    isTv = true;
                  } catch (_) {}
                }

                if (isTv && seen.add(ip) && !controller.isClosed) {
                  final meta = await resolveTvMetadata(ip);
                  if (!controller.isClosed) {
                    controller.add(DiscoveredTv(
                      meta.name,
                      ip,
                      manufacturer: meta.manufacturer,
                      model: meta.model,
                    ));
                  }
                }
              } catch (_) {}
            }());
          }

          await Future.wait(futures);
        }
      }
    } catch (_) {}
  }

  static Future<TvMetadata> resolveTvMetadata(String ip) async {
    String? foundName;
    String? foundManufacturer;
    String? foundModel;

    // 1. DIAL SSDP device description XML (porta 8008)
    HttpClient? client1;
    try {
      client1 = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 700);
      final req = await client1
          .getUrl(Uri.parse('http://$ip:8008/ssdp/device-desc.xml'));
      final resp =
          await req.close().timeout(const Duration(milliseconds: 700));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final fnMatch =
            RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(body);
        final mfMatch =
            RegExp(r'<manufacturer>(.*?)</manufacturer>').firstMatch(body);
        final mdMatch =
            RegExp(r'<modelName>(.*?)</modelName>').firstMatch(body);

        if (fnMatch != null) foundName = fnMatch.group(1)?.trim();
        if (mfMatch != null) foundManufacturer = mfMatch.group(1)?.trim();
        if (mdMatch != null) foundModel = mdMatch.group(1)?.trim();
      }
    } catch (_) {} finally {
      try {
        client1?.close(force: true);
      } catch (_) {}
    }

    // 2. Google Cast / DIAL REST endpoint (porta 8008)
    if (foundName == null || foundName.isEmpty) {
      HttpClient? client2;
      try {
        client2 = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 700);
        final req = await client2.getUrl(
            Uri.parse('http://$ip:8008/setup/eureka_info'));
        final resp =
            await req.close().timeout(const Duration(milliseconds: 700));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          foundName ??= json['name'] as String?;
          final info = json['device_info'] as Map<String, dynamic>?;
          foundManufacturer ??= info?['manufacturer'] as String?;
          foundModel ??= info?['model_name'] as String?;
        }
      } catch (_) {} finally {
        try {
          client2?.close(force: true);
        } catch (_) {}
      }
    }

    // 3. DNS reverso
    if (foundName == null || foundName.isEmpty) {
      try {
        final host = await InternetAddress(ip)
            .reverse()
            .timeout(const Duration(milliseconds: 400));
        if (host.host != ip) {
          final clean = host.host
              .replaceAll('.local', '')
              .replaceAll('.lan', '')
              .replaceAll('.home', '');
          foundName = clean;
        }
      } catch (_) {}
    }

    final finalName = (foundName != null && foundName.isNotEmpty)
        ? foundName
        : (foundModel != null && foundModel.isNotEmpty)
            ? foundModel
            : 'Android TV ($ip)';

    return TvMetadata(
      name: finalName,
      manufacturer: foundManufacturer,
      model: foundModel,
    );
  }

  static Future<String> resolveTvName(String ip) async {
    final meta = await resolveTvMetadata(ip);
    return meta.displayName;
  }
}

extension TvMetadataExtension on TvMetadata {
  String get displayName => name;
}
