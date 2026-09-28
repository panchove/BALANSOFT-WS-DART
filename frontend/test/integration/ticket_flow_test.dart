import 'dart:convert';
import 'dart:typed_data';

import 'package:balansoft_ws/data/datasources/local/database_helper.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/weighing_repository.dart';
import 'package:balansoft_ws/domain/entities/printer_preset.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeWifiConnectivity extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged =>
      const Stream<ConnectivityResult>.empty();
}

class _TicketMockAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    if (options.path.endsWith('/pdf')) {
      return ResponseBody.fromBytes(
        Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), // %PDF
        200,
        headers: {
          Headers.contentTypeHeader: ['application/pdf'],
        },
      );
    }

    if (options.path.endsWith('/txt')) {
      return ResponseBody.fromString(
        'BOLETO DE PESAJE\nTA-00000001\nPESO NETO: 5.000 KG',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
        },
      );
    }

    return ResponseBody.fromString('{"ok": true}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Flujo de Integración: Presets y Generación de Tickets', () {
    late _TicketMockAdapter mockAdapter;
    late ApiClient apiClient;
    late WeighingRepository repository;

    setUp(() {
      ConnectivityPlatform.instance = _FakeWifiConnectivity();
      SharedPreferences.setMockInitialValues({});
      mockAdapter = _TicketMockAdapter();
      final dio = Dio();
      dio.httpClientAdapter = mockAdapter;
      apiClient = ApiClient(dio: dio);
      repository = WeighingRepository(
        apiClient: apiClient,
        dbHelper: DatabaseHelper(),
        connectivity: Connectivity(),
      );
    });

    test('Persistencia y recuperación de PrinterPreset en LocalStorage', () async {
      final storage = LocalStorage();

      // Inicialmente devuelve preset por defecto
      final inicial = await storage.getPrinterPreset();
      expect(inicial.nombreImpresora, 'Impresora Térmica POS-80');
      expect(inicial.boletosPorHoja, 1);

      // Guardar preset personalizado
      const personalizado = PrinterPreset(
        nombreImpresora: 'Epson LX-300',
        tipoImpresora: 'MATRIZ_PUNTO',
        tamanoPapel: 'Letter',
        orientacion: 'portrait',
        boletosPorHoja: 3,
        mostrarEncabezado: true,
        mostrarDetalles: false,
      );

      await storage.savePrinterPreset(personalizado);

      // Recuperar y validar
      final recuperado = await storage.getPrinterPreset();
      expect(recuperado.nombreImpresora, 'Epson LX-300');
      expect(recuperado.tipoImpresora, 'MATRIZ_PUNTO');
      expect(recuperado.boletosPorHoja, 3);
      expect(recuperado.mostrarDetalles, isFalse);
    });

    test('WeighingRepository.getTicketPdf envía query params exactos a la API', () async {
      const boletoId = 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf';
      final response = await repository.getTicketPdf(
        boletoId,
        boletosPorHoja: 3,
        tamanoPapel: 'Letter',
        orientacion: 'landscape',
        mostrarEncabezado: false,
        mostrarDetalles: true,
      );

      expect(response.statusCode, 200);
      expect(mockAdapter.lastRequest, isNotNull);
      expect(mockAdapter.lastRequest!.path, endsWith('/weighing/$boletoId/pdf'));
      expect(mockAdapter.lastRequest!.queryParameters['boletos_por_hoja'], 3);
      expect(mockAdapter.lastRequest!.queryParameters['tamano_papel'], 'Letter');
      expect(mockAdapter.lastRequest!.queryParameters['orientacion'], 'landscape');
      expect(mockAdapter.lastRequest!.queryParameters['mostrar_encabezado'], isFalse);
      expect(mockAdapter.lastRequest!.queryParameters['mostrar_detalles'], isTrue);
    });

    test('WeighingRepository.getTicketTxt solicita endpoint /txt correctamente', () async {
      const boletoId = 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf';
      final response = await repository.getTicketTxt(boletoId);

      expect(response.statusCode, 200);
      expect(mockAdapter.lastRequest, isNotNull);
      expect(mockAdapter.lastRequest!.path, endsWith('/weighing/$boletoId/txt'));
      final texto = utf8.decode(response.data as List<int>);
      expect(texto, contains('BOLETO DE PESAJE'));
    });
  });
}
