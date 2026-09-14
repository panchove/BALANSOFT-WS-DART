import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/catalog_resources.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

class CatalogEditScreen extends StatefulWidget {
  final CatalogResource recurso;
  final Map<String, dynamic>? inicial;

  const CatalogEditScreen({
    super.key,
    required this.recurso,
    this.inicial,
  });

  @override
  State<CatalogEditScreen> createState() => _CatalogEditScreenState();
}

class _CatalogEditScreenState extends State<CatalogEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _dropdownVals = {};
  final Map<String, List<PhotoCaptured>> _fotos = {};
  Map<String, List<Map<String, dynamic>>> _referencias = const {};
  bool _guardando = false;

  bool get _esNuevo => widget.inicial == null;

  @override
  void initState() {
    super.initState();
    final inicial = widget.inicial ?? const <String, dynamic>{};
    for (final campo in widget.recurso.campos) {
      _ctrls[campo.key] =
          TextEditingController(text: _toText(campo, inicial[campo.key]));
      if (campo.tipo == CatalogFieldType.dropdown) {
        final v = inicial[campo.key];
        if (v != null && '$v'.isNotEmpty) {
          _dropdownVals[campo.key] = '$v';
        } else if (campo.opciones != null && campo.opciones!.isNotEmpty) {
          _dropdownVals[campo.key] = campo.opciones!.first;
        } else {
          _dropdownVals[campo.key] = '';
        }
      }
    }
    _cargarReferencias();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _toText(CatalogField campo, dynamic valor) {
    if (valor == null) return '';
    if (campo.tipo == CatalogFieldType.numero ||
        campo.tipo == CatalogFieldType.entero) {
      if (valor is num) return valor.toString();
    }
    return '$valor';
  }

  Future<void> _cargarReferencias() async {
    final paths = widget.recurso.campos
        .map((c) => c.catalogoPath)
        .whereType<String>()
        .toSet();
    if (paths.isEmpty) return;
    final api = di.sl<ApiClient>();
    final refs = <String, List<Map<String, dynamic>>>{};
    for (final p in paths) {
      try {
        final r = await api.getList(p);
        final data = r.data;
        if (data is List) {
          refs[p] = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          refs[p] = const [];
        }
      } catch (_) {
        refs[p] = const [];
      }
    }
    if (mounted) setState(() => _referencias = refs);
  }

  Map<String, dynamic>? _buildBody() {
    final body = <String, dynamic>{};
    for (final campo in widget.recurso.campos) {
      if (campo.tipo == CatalogFieldType.foto) continue;
      if (campo.tipo == CatalogFieldType.dropdown) {
        final valor = _dropdownVals[campo.key];
        if (valor != null && valor.isNotEmpty) {
          body[campo.key] = valor;
        } else if (campo.requerido) {
          _errorSnack('Seleccione ${campo.label.toLowerCase()}');
          return null;
        }
        continue;
      }
      final texto = _ctrls[campo.key]!.text.trim();
      if (texto.isEmpty) {
        if (campo.requerido) {
          _errorSnack('${campo.label} es obligatorio');
          return null;
        }
        continue;
      }
      switch (campo.tipo) {
        case CatalogFieldType.entero:
          final entero = int.tryParse(texto);
          if (entero == null) {
            _errorSnack('${campo.label} debe ser un número entero');
            return null;
          }
          body[campo.key] = entero;
        case CatalogFieldType.numero:
          final numero = double.tryParse(texto);
          if (numero == null) {
            _errorSnack('${campo.label} debe ser un número');
            return null;
          }
          body[campo.key] = numero;
        case CatalogFieldType.email:
          if (!Validators.isEmail(texto)) {
            _errorSnack('Ingrese un email válido');
            return null;
          }
          body[campo.key] = texto;
        case CatalogFieldType.texto:
        case CatalogFieldType.multilinea:
        case CatalogFieldType.dropdown:
          body[campo.key] = texto;
        case CatalogFieldType.foto:
          continue;
      }
    }
    return body;
  }

  void _errorSnack(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: SwsColors.danger),
    );
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final body = _buildBody();
    if (body == null) return;

    setState(() => _guardando = true);
    final api = di.sl<ApiClient>();
    try {
      for (final campo in widget.recurso.campos) {
        if (campo.tipo != CatalogFieldType.foto) continue;
        final fotos = _fotos[campo.key] ?? const <PhotoCaptured>[];
        if (fotos.isEmpty) continue;
        final foto = fotos.first;
        body[campo.key] = await api.uploadPhotoFile(
          foto.bytes,
          foto.nombre,
          carpeta: widget.recurso.clave,
        );
      }
      if (_esNuevo) {
        await api.createItem(widget.recurso.listaPath, body);
      } else {
        final id = widget.recurso.idDe(widget.inicial ?? const {});
        await api.updateItem(widget.recurso.itemPath(id), body);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.recurso.singular} guardado'),
          backgroundColor: SwsColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _errorSnack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${_esNuevo ? 'Nuevo' : 'Editar'} ${widget.recurso.singular}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final campo in widget.recurso.campos) ...[
                _buildCampo(campo),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_esNuevo ? 'Guardar' : 'Actualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCampo(CatalogField campo) {
    if (campo.tipo == CatalogFieldType.foto) {
      return _CampoFoto(
        label: campo.label,
        urlInicial: _esNuevo ? null : (widget.inicial?[campo.key] as String?),
        fotos: _fotos[campo.key] ?? const <PhotoCaptured>[],
        onChanged: (f) => setState(() => _fotos[campo.key] = f),
      );
    }
    if (campo.tipo == CatalogFieldType.dropdown) {
      return _buildDropdown(campo);
    }
    final teclado = switch (campo.tipo) {
      CatalogFieldType.numero => const TextInputType.numberWithOptions(
          decimal: true),
      CatalogFieldType.entero => TextInputType.number,
      CatalogFieldType.email => TextInputType.emailAddress,
      _ => null,
    };
    final validadores = <String? Function(String?)>[
      if (campo.requerido) Validators.required,
      if (campo.tipo == CatalogFieldType.email)
        (v) => (v == null || v.isEmpty || Validators.isEmail(v))
            ? null
            : 'Email inválido',
    ];
    return TextFormField(
      controller: _ctrls[campo.key],
      keyboardType: teclado,
      maxLines: campo.tipo == CatalogFieldType.multilinea ? 3 : 1,
      inputFormatters: campo.tipo == CatalogFieldType.entero
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        labelText:
            campo.label + (campo.requerido ? ' *' : ''),
        prefixIcon: Icon(campo.icono),
        hintText: campo.hint,
      ),
      validator: validadores.isEmpty
          ? null
          : (v) {
              for (final fn in validadores) {
                final res = fn(v);
                if (res != null) return res;
              }
              return null;
            },
    );
  }

  Widget _buildDropdown(CatalogField campo) {
    List<DropdownMenuItem<String>> items;
    if (campo.opciones != null) {
      items = [
        for (final op in campo.opciones!)
          DropdownMenuItem(value: op, child: Text(op)),
      ];
    } else {
      final refs = _referencias[campo.catalogoPath] ?? const [];
      items = [
        if (_dropdownVals[campo.key] == null || _dropdownVals[campo.key]!.isEmpty)
          const DropdownMenuItem(
            value: '',
            child: Text('— Seleccionar —'),
          ),
        for (final ref in refs)
          DropdownMenuItem(
            value: '${ref[campo.catalogoIdKey] ?? ''}',
            child: Text('${ref[campo.catalogoTituloKey] ?? ''}'),
          ),
      ];
    }
    final valor = _dropdownVals[campo.key] ?? '';
    final valorEfectivo = items.any((i) => i.value == valor)
        ? valor
        : (items.isEmpty ? null : items.first.value);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: campo.label + (campo.requerido ? ' *' : ''),
        prefixIcon: Icon(campo.icono),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valorEfectivo,
          isExpanded: true,
          hint: const Text('— Seleccionar —'),
          items: items,
          onChanged: (v) => setState(() {
            if (v != null) _dropdownVals[campo.key] = v;
          }),
        ),
      ),
    );
  }
}

class _CampoFoto extends StatefulWidget {
  final String label;
  final String? urlInicial;
  final List<PhotoCaptured> fotos;
  final ValueChanged<List<PhotoCaptured>> onChanged;

  const _CampoFoto({
    required this.label,
    this.urlInicial,
    required this.fotos,
    required this.onChanged,
  });

  @override
  State<_CampoFoto> createState() => _CampoFotoState();
}

class _CampoFotoState extends State<_CampoFoto> {
  final _picker = ImagePicker();

  Future<void> _tomar() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (xfile != null) await _agregar(xfile);
    } catch (_) {
      _errorSnack('No se pudo tomar la foto');
    }
  }

  Future<void> _cargar() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (xfile != null) await _agregar(xfile);
    } catch (_) {
      _errorSnack('No se pudo cargar la imagen');
    }
  }

  Future<void> _agregar(XFile xfile) async {
    final bytes = await xfile.readAsBytes();
    final nombre = xfile.name.isEmpty
        ? 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg'
        : xfile.name;
    widget.onChanged([PhotoCaptured(bytes: bytes, nombre: nombre)]);
  }

  void _errorSnack(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: SwsColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fotos = widget.fotos;
    final tieneLocal = fotos.isNotEmpty;
    final urlRemota = (!tieneLocal && widget.urlInicial != null && widget.urlInicial!.isNotEmpty)
        ? widget.urlInicial!
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image_outlined, size: 18, color: SwsColors.gray500),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const Spacer(),
            Text(
              urlRemota != null ? 'Guardada' : '${fotos.length}/1',
              style: const TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tieneLocal)
          _thumbLocal(fotos.first)
        else if (urlRemota != null)
          _thumbRemota(urlRemota)
        else
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: SwsColors.light,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SwsColors.gray200),
            ),
            child: const Center(
              child: Text(
                'Sin foto',
                style: TextStyle(color: SwsColors.gray400),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: fotos.isEmpty ? _tomar : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(tieneLocal ? 'Foto tomada' : 'Tomar foto'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SwsColors.primary,
                  side: BorderSide(color: SwsColors.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: fotos.isEmpty ? _cargar : null,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(tieneLocal ? 'Lista' : 'Cargar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SwsColors.primary,
                  side: BorderSide(color: SwsColors.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _thumbLocal(PhotoCaptured foto) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            foto.bytes,
            height: 90,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => widget.onChanged(const []),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumbRemota(String url) {
    final api = di.sl<ApiClient>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        api.mediaUrl(url),
        height: 90,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 90,
          decoration: BoxDecoration(
            color: SwsColors.light,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: SwsColors.gray400),
          ),
        ),
      ),
    );
  }
}