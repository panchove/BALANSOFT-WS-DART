import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

enum CrearCampoTipo { texto, multilinea, numero, email, dropdown, booleano }

class CrearCampoSpec {
  final String key;
  final String label;
  final IconData icon;
  final CrearCampoTipo tipo;
  final bool requerido;
  final List<String>? opciones;
  final String? initial;
  final bool precargarTexto;

  const CrearCampoSpec({
    required this.key,
    required this.label,
    required this.icon,
    this.tipo = CrearCampoTipo.texto,
    this.requerido = false,
    this.opciones,
    this.initial,
    this.precargarTexto = false,
  });

  CrearCampoSpec copyWith({String? initial}) => CrearCampoSpec(
        key: key,
        label: label,
        icon: icon,
        tipo: tipo,
        requerido: requerido,
        opciones: opciones,
        initial: initial ?? this.initial,
        precargarTexto: precargarTexto,
      );
}

Future<Map<String, dynamic>?> showCreateItemDialog({
  required BuildContext context,
  required String titulo,
  required IconData icon,
  required String path,
  required List<CrearCampoSpec> campos,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateItemDialog(
      titulo: titulo,
      icon: icon,
      path: path,
      campos: campos,
    ),
  );
}

class _CreateItemDialog extends StatefulWidget {
  final String titulo;
  final IconData icon;
  final String path;
  final List<CrearCampoSpec> campos;

  const _CreateItemDialog({
    required this.titulo,
    required this.icon,
    required this.path,
    required this.campos,
  });

  @override
  State<_CreateItemDialog> createState() => _CreateItemDialogState();
}

class _CreateItemDialogState extends State<_CreateItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _dropdownVals = {};
  final Map<String, bool> _boolVals = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _guardando = false;

  static bool _esCampoTexto(CrearCampoSpec campo) {
    return switch (campo.tipo) {
      CrearCampoTipo.texto ||
      CrearCampoTipo.multilinea ||
      CrearCampoTipo.numero ||
      CrearCampoTipo.email =>
        true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    for (final campo in widget.campos) {
      if (_esCampoTexto(campo)) _focusNodes[campo.key] = FocusNode();
      if (campo.tipo == CrearCampoTipo.booleano) {
        _boolVals[campo.key] = campo.initial == 'true';
        continue;
      }
      _ctrls[campo.key] = TextEditingController(text: campo.initial ?? '');
      if (campo.tipo == CrearCampoTipo.dropdown) {
        final initial = campo.initial;
        _dropdownVals[campo.key] =
            (initial != null && campo.opciones?.contains(initial) == true)
                ? initial
                : (campo.opciones?.isNotEmpty == true
                    ? campo.opciones!.first
                    : '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Avanza al siguiente campo de texto (o guarda si es el último).
  void _avanzar(CrearCampoSpec actual) {
    final textos = widget.campos.where(_esCampoTexto).toList();
    final i = textos.indexOf(actual);
    if (i >= 0 && i < textos.length - 1) {
      _focusNodes[textos[i + 1].key]?.requestFocus();
    } else {
      _guardar();
    }
  }

  Map<String, dynamic>? _buildBody() {
    final body = <String, dynamic>{};
    for (final campo in widget.campos) {
      if (campo.tipo == CrearCampoTipo.booleano) {
        body[campo.key] = _boolVals[campo.key] ?? false;
        continue;
      }
      if (campo.tipo == CrearCampoTipo.dropdown) {
        final valor = _dropdownVals[campo.key];
        if (valor == null || valor.isEmpty) {
          if (campo.requerido) {
            _errorSnack('Seleccione ${campo.label.toLowerCase()}');
            return null;
          }
        } else {
          body[campo.key] = valor;
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
        case CrearCampoTipo.numero:
          final numero = double.tryParse(texto);
          if (numero == null) {
            _errorSnack('${campo.label} debe ser un número');
            return null;
          }
          body[campo.key] = numero;
        case CrearCampoTipo.email:
          if (!Validators.isEmail(texto)) {
            _errorSnack('Ingrese un email válido');
            return null;
          }
          body[campo.key] = texto;
        default:
          body[campo.key] = texto;
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
    if (_guardando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final body = _buildBody();
    if (body == null) return;

    setState(() => _guardando = true);
    try {
      final api = di.sl<ApiClient>();
      final response = await api.createItem(widget.path, body);
      final json = response.data;
      if (!mounted) return;
      if (json is Map) {
        Navigator.of(context).pop(Map<String, dynamic>.from(json));
      } else {
        _errorSnack('El servidor no devolvió el registro creado.');
      }
    } catch (e) {
      if (!mounted) return;
      _errorSnack('Error al crear: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.icon, color: SwsColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.titulo)),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final campo in widget.campos) ...[
                _buildCampo(campo),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _guardando ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }

  Widget _buildCampo(CrearCampoSpec campo) {
    if (campo.tipo == CrearCampoTipo.booleano) {
      return SwitchListTile(
        title: Text(campo.label),
        value: _boolVals[campo.key] ?? false,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        onChanged: (v) => setState(() => _boolVals[campo.key] = v),
      );
    }
    if (campo.tipo == CrearCampoTipo.dropdown) {
      final opciones = campo.opciones ?? const <String>[];
      return InputDecorator(
        decoration: InputDecoration(
          labelText: campo.label + (campo.requerido ? ' *' : ''),
          prefixIcon: Icon(campo.icon),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: opciones.contains(_dropdownVals[campo.key])
                ? _dropdownVals[campo.key]
                : (opciones.isEmpty ? null : opciones.first),
            isExpanded: true,
            items: [
              for (final op in opciones)
                DropdownMenuItem(value: op, child: Text(op)),
            ],
            onChanged: (v) => setState(() {
              if (v != null) _dropdownVals[campo.key] = v;
            }),
          ),
        ),
      );
    }
    final teclado = switch (campo.tipo) {
      CrearCampoTipo.numero =>
        const TextInputType.numberWithOptions(decimal: true),
      CrearCampoTipo.email => TextInputType.emailAddress,
      _ => null,
    };
    final validadores = <String? Function(String?)>[
      if (campo.requerido) Validators.required,
      if (campo.tipo == CrearCampoTipo.email)
        (v) => (v == null || v.isEmpty || Validators.isEmail(v))
            ? null
            : 'Email inválido',
    ];
    final textos = widget.campos.where(_esCampoTexto).toList();
    final esUltimo = textos.isNotEmpty && textos.last.key == campo.key;
    return TextFormField(
      controller: _ctrls[campo.key],
      focusNode: _focusNodes[campo.key],
      keyboardType: teclado,
      maxLines: campo.tipo == CrearCampoTipo.multilinea ? 3 : 1,
      textInputAction:
          esUltimo ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: (_) => _avanzar(campo),
      inputFormatters: campo.tipo == CrearCampoTipo.numero
          ? [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
            ]
          : null,
      decoration: InputDecoration(
        labelText: campo.label + (campo.requerido ? ' *' : ''),
        prefixIcon: Icon(campo.icon),
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
}