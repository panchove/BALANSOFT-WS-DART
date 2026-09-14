import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import 'create_item_dialog.dart';

class CreatableSpec<T> {
  final String path;
  final String titulo;
  final IconData icon;
  final T Function(Map<String, dynamic> json) parse;
  final List<CrearCampoSpec> campos;

  const CreatableSpec({
    required this.path,
    required this.titulo,
    required this.icon,
    required this.parse,
    required this.campos,
  });
}

class _CrearSugerencia {
  final String texto;
  const _CrearSugerencia(this.texto);
}

class AutocompleteCreatable<T extends Object> extends StatefulWidget {
  final List<T> items;
  final String Function(T) label;
  final String Function(T) search;
  final String fieldName;
  final IconData icon;
  final bool required;
  final ValueChanged<T> onSelected;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<T>? onCreated;
  final CreatableSpec<T>? crear;
  final String? hint;
  final Key? fieldKey;

  const AutocompleteCreatable({
    super.key,
    required this.items,
    required this.label,
    required this.search,
    required this.fieldName,
    required this.icon,
    this.required = false,
    required this.onSelected,
    this.onTextChanged,
    this.onCreated,
    this.crear,
    this.hint,
    this.fieldKey,
  });

  @override
  State<AutocompleteCreatable<T>> createState() =>
      _AutocompleteCreatableState<T>();
}

class _AutocompleteCreatableState<T extends Object>
    extends State<AutocompleteCreatable<T>> {
  TextEditingController? _controller;
  String _ultimoQuery = '';

  Future<void> _crearNuevo() async {
    final spec = widget.crear;
    if (spec == null) return;
    final campos = [
      for (final c in spec.campos)
        c.precargarTexto ? c.copyWith(initial: _ultimoQuery) : c,
    ];
    final creado = await showCreateItemDialog(
      context: context,
      titulo: spec.titulo,
      icon: spec.icon,
      path: spec.path,
      campos: campos,
    );
    if (creado == null || !mounted) return;
    try {
      final item = spec.parse(creado);
      _controller?.text = widget.label(item);
      widget.onSelected(item);
      widget.onCreated?.call(item);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo interpretar el registro creado'),
          backgroundColor: SwsColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Object>(
      displayStringForOption: (option) => option is _CrearSugerencia
          ? option.texto
          : widget.label(option as T),
      optionsBuilder: (value) {
        final texto = value.text.trim();
        _ultimoQuery = texto;
        if (texto.isEmpty) return widget.items;
        final lower = texto.toLowerCase();
        final matches = widget.items
            .where((i) => widget.search(i).toLowerCase().contains(lower))
            .toList();
        final spec = widget.crear;
        if (spec == null) return matches;
        final exacto =
            widget.items.any((i) => widget.label(i).toLowerCase() == lower);
        if (!exacto) {
          return [...matches, _CrearSugerencia('+ Crear "$texto"')];
        }
        return matches;
      },
      onSelected: (option) {
        if (option is _CrearSugerencia) {
          _crearNuevo();
          return;
        }
        final item = option as T;
        _controller?.text = widget.label(item);
        widget.onSelected(item);
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        _controller = textController;
        return TextFormField(
          key: widget.fieldKey,
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText:
                widget.fieldName + (widget.required ? ' *' : ''),
            prefixIcon: Icon(widget.icon),
            hintText: widget.hint,
            suffixIcon: widget.crear != null
                ? IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Crear nuevo',
                    onPressed: () {
                      if (_ultimoQuery.isNotEmpty) _crearNuevo();
                    },
                  )
                : null,
          ),
          textCapitalization: TextCapitalization.none,
          validator: widget.required
              ? (v) => Validators.required(v, widget.fieldName)
              : null,
          onChanged: (value) => widget.onTextChanged?.call(value),
        );
      },
    );
  }
}