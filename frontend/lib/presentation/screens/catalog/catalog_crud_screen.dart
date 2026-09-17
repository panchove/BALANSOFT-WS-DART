import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/catalog_resources.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/catalog_crud/catalog_crud_cubit.dart';
import 'catalog_edit_screen.dart';

enum _FiltroTipo { cliente, proveedor, ambos }

class CatalogCrudScreen extends StatefulWidget {
  final CatalogResource recurso;

  const CatalogCrudScreen({super.key, required this.recurso});

  @override
  State<CatalogCrudScreen> createState() => _CatalogCrudScreenState();
}

class _CatalogCrudScreenState extends State<CatalogCrudScreen> {
  final _searchCtrl = TextEditingController();
  _FiltroTipo _tipoSeleccionado = _FiltroTipo.ambos;

  /// El cubit se resuelve una sola vez en el State: los métodos pueden usarlo
  /// sin depender de `context.read` (que aquí se ejecuta por encima del
  /// provider, causando ProviderNotFoundError).
  late final CatalogCrudCubit _cubit = di.sl<CatalogCrudCubit>();

  @override
  void initState() {
    super.initState();
    _cubit.cargar(widget.recurso);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _pasaFiltro(Map<String, dynamic> fila) {
    if (!widget.recurso.pasaTipoFiltro(fila)) return false;
    final tipo = (fila['tipo'] as String?) ?? '';
    switch (_tipoSeleccionado) {
      case _FiltroTipo.ambos:
        return true;
      case _FiltroTipo.cliente:
        return tipo == 'CLIENTE' || tipo == 'AMBOS';
      case _FiltroTipo.proveedor:
        return tipo == 'PROVEEDOR' || tipo == 'AMBOS';
    }
  }

  Future<void> _abrirEditor({Map<String, dynamic>? inicial}) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogEditScreen(
        recurso: widget.recurso,
        inicial: inicial,
        modal: true,
      ),
    );
    if (guardado == true && mounted) {
      _cubit.cargar(widget.recurso);
    }
  }

  Widget _fotoLeading(Map<String, dynamic> fila) {
    final clave = widget.recurso.campoFotoKey;
    final url = clave != null ? fila[clave] as String? : null;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        backgroundColor: SwsColors.blue100,
        foregroundColor: SwsColors.primary,
        child: Icon(widget.recurso.icono, size: 20),
      );
    }
    final api = di.sl<ApiClient>();
    return ClipOval(
      child: Image.network(
        api.mediaUrl(url),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          backgroundColor: SwsColors.blue100,
          foregroundColor: SwsColors.primary,
          child: Icon(widget.recurso.icono, size: 20),
        ),
      ),
    );
  }

  Future<void> _confirmarEliminar(
      CatalogCrudCubit cubit, Map<String, dynamic> fila) async {
    final id = widget.recurso.idDe(fila);
    final titulo = widget.recurso.tituloFila(fila);
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: Text(
            '¿Eliminar "${titulo.isNotEmpty ? titulo : id}"?\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SwsColors.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado == true && mounted) {
      cubit.eliminar(widget.recurso, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.recurso.plural)),
        body: BlocBuilder<CatalogCrudCubit, CatalogCrudState>(
          builder: (context, state) {
            final cubit = context.read<CatalogCrudCubit>();
            if (state.cargando) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: SwsColors.danger),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SwsColors.gray600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => cubit.cargar(widget.recurso),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }
            if (state.items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.recurso.icono,
                        size: 56, color: SwsColors.gray400),
                    const SizedBox(height: 12),
                    Text('No hay ${widget.recurso.plural.toLowerCase()}',
                        style: const TextStyle(color: SwsColors.gray500)),
                  ],
                ),
              );
            }
            final query = _searchCtrl.text.trim().toLowerCase();
            final filtrados = query.isEmpty
                ? state.items.where(_pasaFiltro).toList()
                : state.items.where((fila) {
                    if (!_pasaFiltro(fila)) return false;
                    final titulo =
                        widget.recurso.tituloFila(fila).toLowerCase();
                    final sub = widget.recurso.subtituloFila
                            ?.call(fila)
                            ?.toLowerCase() ??
                        '';
                    final id = widget.recurso.idDe(fila).toLowerCase();
                    return titulo.contains(query) ||
                        sub.contains(query) ||
                        id.contains(query);
                  }).toList();
            return Column(
              children: [
                if (widget.recurso.filtrarTipoUI)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_FiltroTipo>(
                        segments: const [
                          ButtonSegment(
                            value: _FiltroTipo.cliente,
                            label: Text('Cliente'),
                          ),
                          ButtonSegment(
                            value: _FiltroTipo.proveedor,
                            label: Text('Proveedor'),
                          ),
                          ButtonSegment(
                            value: _FiltroTipo.ambos,
                            label: Text('Ambos'),
                          ),
                        ],
                        selected: {_tipoSeleccionado},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (sel) =>
                            setState(() => _tipoSeleccionado = sel.first),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'Buscar ${widget.recurso.plural.toLowerCase()}…',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => cubit.cargar(widget.recurso),
                    child: filtrados.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('Sin coincidencias')),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filtrados.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemBuilder: (context, index) {
                              final fila = filtrados[index];
                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: ListTile(
                                  leading: _fotoLeading(fila),
                                  title: Text(widget.recurso.tituloFila(fila)),
                                  subtitle: widget.recurso.subtituloFila
                                              ?.call(fila) !=
                                          null
                                      ? Text(
                                          widget.recurso.subtituloFila!
                                              .call(fila)!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  trailing: IconButton(
                                    tooltip: 'Eliminar',
                                    icon: Icon(
                                      state.eliminando
                                          ? Icons.hourglass_top
                                          : Icons.delete_outline,
                                      color: SwsColors.gray500,
                                    ),
                                    onPressed: state.eliminando
                                        ? null
                                        : () => _confirmarEliminar(cubit, fila),
                                  ),
                                  onTap: () => _abrirEditor(inicial: fila),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Nuevo ${widget.recurso.singular}',
          onPressed: () => _abrirEditor(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
