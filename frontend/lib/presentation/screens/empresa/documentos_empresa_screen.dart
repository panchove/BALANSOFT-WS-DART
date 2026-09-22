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
  String _formatoTicket = 'PDF';

  // Series de numeración (CRUD; el campo de trabajo elige cuál usar)
  List<dynamic> _series = const [];
  String? _idSerieActiva;
  bool _seriesCargando = false;
  bool _guardandoSerie = false;
  String? _errorSeries;

  final _serieNombreCtrl = TextEditingController();
  final _seriePrefijoCtrl = TextEditingController();
  final _serieDigitosCtrl = TextEditingController();

  bool get _esAdmin => _usuario?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarSeries();
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
        _formatoTicket = '${perfil['formato_ticket'] ?? 'PDF'}';
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

  // ── CRUD Series de numeración (el boleto elige cuál usar) ──
  Future<void> _cargarSeries() async {
    setState(() {
      _seriesCargando = true;
      _errorSeries = null;
    });
    try {
      final resp = await di.sl<ApiClient>().listSeries();
      final data = resp.data;
      final listado = (data is List)
          ? data.cast<Map<String, dynamic>>()
          : (data is Map && data['items'] is List)
              ? (data['items'] as List).cast<Map<String, dynamic>>()
              : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _series = listado;
        final activa = listado.where((s) => s['activa'] == true).firstOrNull;
        final idActiva = activa != null
            ? activa['id_serie']
            : (listado.isNotEmpty ? listado.first['id_serie'] : null);
        _idSerieActiva = idActiva?.toString();
        _seriesCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _seriesCargando = false;
        _errorSeries = 'No se pudo cargar las series: $e';
      });
    }
  }

  Future<void> _guardarSerie() async {
    if (!_esAdmin || _guardandoSerie) return;
    final nombre = _serieNombreCtrl.text.trim();
    final prefijo = _seriePrefijoCtrl.text.trim();
    String? activarId;
    if (nombre.isEmpty || prefijo.isEmpty) {
      _snack('Nombre y prefijo son obligatorios', error: true);
      return;
    }
    final digitosCtrl = _serieDigitosCtrl.text.trim();
    final digitos = int.tryParse(digitosCtrl);
    if (digitos == null || digitos < 4 || digitos > 12) {
      _snack('Dígitos debe ser un número entre 4 y 12', error: true);
      return;
    }
    setState(() => _guardandoSerie = true);
    try {
      final api = di.sl<ApiClient>();
      final body = <String, dynamic>{
        'nombre': nombre,
        'prefijo': prefijo,
        'digitos': digitos,
      };
      if (_idSerieActiva != null &&
          _series.any((s) => '${s['id_serie']}' == _idSerieActiva)) {
        await api.updateSeries(_idSerieActiva!, body);
        activarId = _idSerieActiva;
      } else {
        final resp = await api.createSeries(body);
        activarId = '${(resp.data as Map)['id_serie']}';
        await api.marcarSerieActiva(activarId);
      }
      _serieNombreCtrl.clear();
      _seriePrefijoCtrl.clear();
      _serieDigitosCtrl.clear();
      await _cargarSeries();
      if (mounted && activarId != null) {
        setState(() => _idSerieActiva = activarId);
      }
      _snack('Serie guardada');
    } catch (e) {
      _snack('Error al guardar la serie: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardandoSerie = false);
    }
  }

  Future<void> _eliminarSerie() async {
    if (!_esAdmin || _idSerieActiva == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar serie'),
        content: const Text(
          '¿Eliminar la serie activa? Los boletos existentes conservan su '
          'número; solo deja de usarse para nuevos boletos.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await di.sl<ApiClient>().deleteSeries(_idSerieActiva!);
      await _cargarSeries();
      _snack('Serie eliminada');
    } catch (e) {
      _snack('Error al eliminar la serie: $e', error: true);
    }
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
        'formato_ticket': _formatoTicket,
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
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                initialValue: _formatoTicket,
                items: const [
                  DropdownMenuItem(value: 'PDF', child: Text('PDF')),
                  DropdownMenuItem(value: 'TXT', child: Text('TXT')),
                ],
                onChanged: _esAdmin
                    ? (v) {
                        if (v != null) setState(() => _formatoTicket = v);
                      }
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Formato al exportar',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(Icons.tag_outlined, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Numeración de documentos',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_seriesCargando)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Recargar series',
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: _cargarSeries,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Los boletos y tickets se numeran de forma correlativa con la '
              'serie seleccionada. Ejemplo: TA-00000001, TA-00000002, …. '
              'La numeración es única por empresa y el siguiente número se '
              'reserva al instante (FOR UPDATE), sin salteos ni duplicados.',
              style: TextStyle(color: SwsColors.gray600, height: 1.4),
            ),
            if (_errorSeries != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorSeries!,
                style: const TextStyle(color: SwsColors.danger, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 14),
            // ── Dropdown: serie que usa el campo de trabajo ──
            DropdownButtonFormField<String>(
              key: const Key('dropdown_serie_activa'),
              initialValue: _idSerieActiva,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Serie a usar en boletos',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final s in _series)
                  DropdownMenuItem(
                    value: s['id_serie'].toString(),
                    child: Text(
                      '${s['nombre']} · ${s['prefijo']}${s['digitos']} '
                      '(siguiente ${s['siguiente']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _idSerieActiva = v);
                try {
                  await di.sl<ApiClient>().marcarSerieActiva(v);
                } catch (e) {
                  _snack('No se pudo activar la serie: $e', error: true);
                }
              },
            ),
            if (_series.isEmpty && !_seriesCargando) ...[
              const SizedBox(height: 10),
              const Text(
                'Aún no hay series. Crea la primera abajo (solo ADMIN) para '
                'que los boletos puedan numerarse.',
                style: TextStyle(color: SwsColors.danger, fontSize: 12.5),
              ),
            ],
            if (_esAdmin) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 6),
              const Text(
                'Series personalizadas',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Cada serie es un modelo: nombre, prefijo y cantidad de '
                'dígitos. Al guardar, queda activa y pasa a numerar los '
                'próximos boletos.',
                style: TextStyle(color: SwsColors.gray600, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _campoSeria('Nombre de la serie', _serieNombreCtrl,
                  hint: 'Ej. Facturación primaria'),
              Row(
                children: [
                  Expanded(
                    child: _campoSeria('Prefijo', _seriePrefijoCtrl,
                        hint: 'Ej. TA-'),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: _campoSeria('Dígitos', _serieDigitosCtrl,
                        hint: '6', teclado: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _guardandoSerie ? null : _guardarSerie,
                    icon: _guardandoSerie
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_outlined, size: 18),
                    label: const Text('Guardar serie'),
                  ),
                  const Spacer(),
                  if (_idSerieActiva != null)
                    OutlinedButton.icon(
                      onPressed: _guardandoSerie ? null : _eliminarSerie,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Eliminar'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _campoSeria(
    String etiqueta,
    TextEditingController controller, {
    String? hint,
    TextInputType? teclado,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: teclado,
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
