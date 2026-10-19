import 'package:balansoft_ws/core/config/company_draft.dart';
import 'package:balansoft_ws/core/widgets/company_setup_form.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompanySetupData _datos({
  String nombreFiscal = 'Variedades S&S C.A.',
  String nombreComercial = 'Variedades',
  String idioma = 'es',
  String formatoTicket = 'PDF',
  String formatoReporte = 'EXCEL',
  String rutaReportes = '/tmp/reportes',
}) {
  return CompanySetupData(
    nombreFiscal: nombreFiscal,
    nombreComercial: nombreComercial,
    rifNit: 'J-31490236-2',
    direccion: 'Calle 1',
    telefono: '0212-1234567',
    email: 'contacto@vs.com.ve',
    idioma: idioma,
    formatoTicket: formatoTicket,
    formatoReporte: formatoReporte,
    rutaReportes: rutaReportes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanyDraft Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('leer() devuelve null si el usuario nunca completó el paso', () async {
      expect(await CompanyDraft.leer(), isNull);
    });

    test('guardar + leer conserva todos los datos de la empresa', () async {
      await CompanyDraft.guardar(_datos());

      final draft = await CompanyDraft.leer();
      expect(draft, isNotNull);
      expect(draft!.vacio, isFalse);
      expect(draft.data.nombreFiscal, 'Variedades S&S C.A.');
      expect(draft.data.rifNit, 'J-31490236-2');
      expect(draft.data.idioma, 'es');
      expect(draft.data.formatoTicket, 'PDF');
      expect(draft.data.formatoReporte, 'EXCEL');
      expect(draft.data.rutaReportes, '/tmp/reportes');
    });

    test('Borrador con nombre fiscal vacío se considera vacío', () async {
      await CompanyDraft.guardar(_datos(nombreFiscal: '   '));
      final draft = await CompanyDraft.leer();
      expect(draft!.vacio, isTrue);
    });

    test('Logo se guarda como base64 y se recupera como bytes', () async {
      final bytes = [137, 80, 78, 71, 13, 10, 26, 10];
      await CompanyDraft.guardar(_datos(), logoBytes: bytes, logoNombre: 'logo.png');

      expect(await CompanyDraft.leerLogoBytes(), bytes);
      expect(await CompanyDraft.leerLogoNombre(), 'logo.png');
    });

    test('limpiar() borra el borrador (tras aplicarse en la BD)', () async {
      await CompanyDraft.guardar(_datos());
      await CompanyDraft.limpiar();

      expect(await CompanyDraft.leer(), isNull);
      expect(await CompanyDraft.leerLogoBytes(), isNull);
    });

    test('toApiBody normaliza el idioma "system" porque el backend solo admite es|en|pt',
        () async {
      final data = _datos(idioma: 'system');

      expect(data.idiomaApi, 'es');
      expect(data.toApiBody()['idioma'], 'es');
    });

    test('toApiBody respeta en y pt, y omite campos vacíos', () async {
      final en = _datos(idioma: 'en');
      expect(en.toApiBody()['idioma'], 'en');

      final pt = _datos(idioma: 'pt', nombreComercial: '');
      final body = pt.toApiBody();
      expect(body['idioma'], 'pt');
      expect(body['nombre_comercial'], isNull);
      expect(body['formato_reporte'], 'EXCEL');
    });
  });
}
