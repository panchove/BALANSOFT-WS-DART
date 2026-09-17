import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/user.dart';
import '../../../injection.dart' as di;

/// Mantenimiento: Definición de Documentos y Empresa.
///
/// Formato de numeración `SERIE-000000001` (docs/MODELO_ESTANDAR.md) y
/// perfil de la empresa (nombre comercial, RIF, dirección, teléfono, email
/// y logo). La edición del perfil es exclusiva del ADMIN; el resto de los
/// roles lo ven en modo lectura.
class DocumentosEmpresaScreen extends StatefulWidget {
  const DocumentosEmpresaScreen({super.key});

  @override
  State<DocumentosEmpresaScreen> createState() =>
      _DocumentosEmpresaScreenState();
}

class _DocumentosEmpresaScreenState extends State<DocumentosEmpresaScreen> {
  final _nombreFiscalCtrl = TextEditingController();
  final _nombreComercialCtrl = TextEditingController();
  final _rifCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  User? _usuario;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _logoUrl;
  List<PhotoCaptured> _logo = const [];

  bool get _esAdmin => _usuario?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreFiscalCtrl.dispose();
    _nombreComercialCtrl.dispose();
    _rifCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final u = await di.sl<LocalStorage>().getCachedUser();
      final perfil = await di.sl<ApiClient>().getEmpresaPerfil();
      if (!mounted) return;
      setState(() {
        _usuario = u;
        _logoUrl = perfil['logo_url'] as String?;
        _logo = const [];
        _nombreFiscalCtrl.text = '${perfil['nombre_fiscal'] ?? ''}';
        _nombreComercialCtrl.text = '${perfil['nombre_comercial'] ?? ''}';
        _rifCtrl.text = '${perfil['rif_nit'] ?? ''}';
        _direccionCtrl.text = '${perfil['direccion'] ?? ''}';
        _telefonoCtrl.text = '${perfil['telefono'] ?? ''}';
        _emailCtrl.text = '${perfil['email'] ?? ''}';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el perfil de la empresa: $e';
      });
    }
  }

  String? _oNulo(String valor) {
    final v = valor.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _guardar() async {
    if (!_esAdmin || _guardando) return;
    final nombreFiscal = _nombreFiscalCtrl.text.trim();
    final rif = _rifCtrl.text.trim();
    if (nombreFiscal.length < 3 || rif.length < 3) {
      _snack('Nombre fiscal y RIF son obligatorios', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final api = di.sl<ApiClient>();
      var logoUrl = _logoUrl;
      if (_logo.isNotEmpty) {
        logoUrl = await api.uploadPhotoFile(
          _logo.first.bytes,
          _logo.first.nombre,
          carpeta: 'empresa',
        );
      }
      await api.updateEmpresaPerfil({
        'nombre_fiscal': nombreFiscal,
        'rif_nit': rif,
        'nombre_comercial': _oNulo(_nombreComercialCtrl.text),
        'direccion': _oNulo(_direccionCtrl.text),
        'telefono': _oNulo(_telefonoCtrl.text),
        'email': _oNulo(_emailCtrl.text),
        'logo_url': logoUrl,
      });
      if (!mounted) return;
      _snack('Perfil de la empresa guardado');
      await _cargar();
    } catch (e) {
      _snack('Error al guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? SwsColors.danger : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documentos y Empresa')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContenido(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: SwsColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLogoCard(),
        const SizedBox(height: 12),
        _buildPerfilCard(),
        const SizedBox(height: 12),
        _buildNumeracionCard(),
      ],
    );
  }

  Widget _buildLogoCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogoPreview(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Logo de la empresa',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Se muestra en tickets y reportes de pesaje.',
                        style: TextStyle(
                            fontSize: 12.5, color: SwsColors.gray600),
                      ),
                      if (!_esAdmin) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Solo el ADMIN puede editarlo.',
                          style: TextStyle(
                              fontSize: 12, color: SwsColors.gray500),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_esAdmin) ...[
              const SizedBox(height: 12),
              PhotoPickerField(
                label: 'Imagen del logo',
                icon: Icons.image_outlined,
                fotos: _logo,
                maxFotos: 1,
                onChanged: (fotos) => setState(() => _logo = fotos),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogoPreview() {
    Widget child;
    if (_logo.isNotEmpty) {
      child = Image.memory(_logo.first.bytes, fit: BoxFit.cover);
    } else if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      final url = di.sl<ApiClient>().mediaUrl(_logoUrl!);
      child = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, color: SwsColors.gray500),
      );
    } else {
      child = const Icon(Icons.business_outlined,
          color: SwsColors.gray500, size: 32);
    }
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: SwsColors.blue100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SwsColors.gray200),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildPerfilCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Perfil de la empresa',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _campo('Nombre fiscal', _nombreFiscalCtrl),
            _campo('Nombre comercial', _nombreComercialCtrl),
            _campo('RIF / NIT', _rifCtrl),
            _campo('Dirección', _direccionCtrl),
            _campo('Teléfono', _telefonoCtrl),
            _campo('Email', _emailCtrl, teclado: TextInputType.emailAddress),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _esAdmin && !_guardando ? _guardar : null,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(
    String etiqueta,
    TextEditingController controller, {
    TextInputType? teclado,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: _esAdmin,
        keyboardType: teclado,
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildNumeracionCard() {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(Icons.tag_outlined, size: 20),
                ),
                SizedBox(width: 12),
                Text(
                  'Numeración de documentos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'Los boletos y tickets se numeran de forma correlativa '
              'con el formato de serie configurado. Ejemplo: '
              'SERIE-000000001, SERIE-000000002, …. '
              'La numeración es única por empresa y la asigna el servidor.',
              style: TextStyle(color: SwsColors.gray600, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              'Formato aplicado',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            SizedBox(height: 6),
            SelectableText(
              'SERIE-000000001',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
