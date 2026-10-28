import 'package:balansoft_ws/core/constants/api_constants.dart';
import 'package:dio/dio.dart';
import 'package:balansoft_ws/core/utils/conceptos_kardex_rules.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:flutter/material.dart';

/// Gestión: Conceptos de Kardex.
///
/// Catálogo de IDs 0-99 que da nombre a los movimientos de inventario. Los
/// conceptos del sistema (00 saldo inicial, 10 ingreso por báscula, 60 despacho
/// por báscula) los genera el propio sistema y solo se pueden renombrar: el
/// backend rechaza (409) su borrado y (422) cualquier cambio de signo.
///
/// Los IDs configurables (01-49 positivos, 50-99 negativos) los crea el ADMIN
/// para los ajustes manuales de inventario.
class ConceptosKardexScreen extends StatefulWidget {
  const ConceptosKardexScreen({super.key});

  @override
  State<ConceptosKardexScreen> createState() => _ConceptosKardexScreenState();
}

class _ConceptosKardexScreenState extends State<ConceptosKardexScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  ApiClient get _api => di.sl<ApiClient>();

  /// Código HTTP de un error de Dio (o `null` si no es de red).
  static int? _codigoHttp(Object error) {
    if (error is DioException) {
      return error.response?.statusCode;
    }
    return null;
  }

  /// Mensaje legible: el backend responde `{"detail": "..."}` cuando puede.
  static String _mensajeDeError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      return error.message ?? 'No se pudo completar la operación';
    }
    return '$error';
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final response = await _api.getList(ApiConstants.conceptosKardex);
      final data = (response.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Signo que corresponde al rango del ID (regla de oro del kardex).
  String _signoDeRango(int id) => signoDeRangoKardex(id);

  Color _colorRango(int id) {
    if (id == 0) return Colors.grey;
    if (id >= 50) return Colors.red;
    return Colors.green;
  }

  IconData _iconoRango(int id) {
    return esConceptoSistema(id) ? Icons.lock_outline : Icons.edit_outlined;
  }

  /// IDs que el usuario puede usar: excluye los reservados 0/10/60 y los que
  /// ya están ocupados por otro concepto de la empresa.
  List<int> _idsLibres() {
    final ocupados = <int>{
      for (final it in _items)
        if (it['id_concepto'] is int) it['id_concepto'] as int,
    }.toList();
    return idsLibresKardex(ocupados);
  }

  Future<void> _nuevo() async {
    final lista = _idsLibres();
    if (lista.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay IDs libres disponibles')),
      );
      return;
    }
    int? seleccionado = lista.first;
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String aplica = 'AMBOS';
    bool activo = true;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final signo = _signoDeRango(seleccionado ?? 1);
          return AlertDialog(
            title: const Text('Nuevo concepto Kardex'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    // ignore: deprecated_member_use
                    value: seleccionado,
                    decoration: const InputDecoration(labelText: 'ID (solo huecos)'),
                    items: [
                      for (final id in lista)
                        DropdownMenuItem(value: id, child: Text('$id')),
                    ],
                    onChanged: (v) => setSt(() => seleccionado = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: aplica,
                    decoration: const InputDecoration(labelText: 'Aplica a'),
                    items: const [
                      DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
                      DropdownMenuItem(value: 'DESPACHO', child: Text('Despacho')),
                      DropdownMenuItem(value: 'AJUSTE', child: Text('Ajuste')),
                      DropdownMenuItem(value: 'AMBOS', child: Text('Ambos')),
                    ],
                    onChanged: (v) => setSt(() => aplica = v ?? 'AMBOS'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Signo:'),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(etiquetaSignoKardex(signo)),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    value: activo,
                    onChanged: (v) => setSt(() => activo = v),
                    title: const Text('Activo'),
                  ),
                ],
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nombreCtrl.text.trim().isEmpty || seleccionado == null) {
                    return;
                  }
                  try {
                    await _api.createItem(
                      ApiConstants.conceptosKardex,
                      {
                        'id_concepto': seleccionado,
                        'nombre': nombreCtrl.text.trim(),
                        'descripcion': descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        'signo': signo,
                        'aplica_a': aplica,
                        'activo': activo,
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _cargar();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editar(Map<String, dynamic> item) async {
    final esSistema = item['es_sistema'] == true;
    final id = item['id_concepto'];
    final nombreCtrl = TextEditingController(text: item['nombre']?.toString() ?? '');
    final descCtrl = TextEditingController(text: item['descripcion']?.toString() ?? '');
    String aplica = item['aplica_a']?.toString() ?? 'AMBOS';
    bool activo = item['activo'] == true;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar concepto $id'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: aplica,
                decoration: const InputDecoration(labelText: 'Aplica a'),
                items: const [
                  DropdownMenuItem(value: 'INGRESO', child: Text('Ingreso')),
                  DropdownMenuItem(value: 'DESPACHO', child: Text('Despacho')),
                  DropdownMenuItem(value: 'AJUSTE', child: Text('Ajuste')),
                  DropdownMenuItem(value: 'AMBOS', child: Text('Ambos')),
                ],
                onChanged: (v) => aplica = v ?? 'AMBOS',
              ),
              SwitchListTile(
                value: activo,
                onChanged: (v) => setState(() => activo = v),
                title: const Text('Activo'),
              ),
              if (esSistema)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('ID y signo bloqueados (concepto del sistema)'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _api.updateItem(
                  ApiConstants.conceptoKardex('$id'),
                  {
                    'nombre': nombreCtrl.text.trim(),
                    'descripcion': descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    'aplica_a': aplica,
                    'activo': activo,
                  },
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _cargar();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Borra un concepto; si el backend responde 409 (tiene movimientos) se
  /// ofrece desactivarlo para conservar el historial.
  Future<void> _borrar(Map<String, dynamic> item) async {
    final id = item['id_concepto'];
    try {
      await _api.deleteItem(ApiConstants.conceptoKardex('$id'));
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Concepto eliminado')),
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = _mensajeDeError(e);
      // 409 = el concepto ya tiene movimientos: no se borra, se desactiva
      // para conservar el historial.
      final conMovimientos = _codigoHttp(e) == 409 ||
          mensaje.toLowerCase().contains('movimientos');
      if (conMovimientos) {
        await _ofrecerDesactivar(item);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensaje)),
        );
      }
    }
  }

  Future<void> _ofrecerDesactivar(Map<String, dynamic> item) async {
    final id = item['id_concepto'];
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Concepto con movimientos'),
        content: const Text(
          'El concepto ya tiene movimientos de kardex: no se puede borrar sin '
          'perder el historial. ¿Desea desactivarlo en su lugar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _api.updateItem(
        ApiConstants.conceptoKardex('$id'),
        {'activo': false},
      );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Concepto desactivado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{
      '00': [],
      '01-49': [],
      '10': [],
      '11-49': [],
      '50-59': [],
      '60': [],
      '61-99': [],
    };
    for (final it in _items) {
      final id = it['id_concepto'];
      if (id is int) {
        grouped[rangoDeKardex(id)]!.add(it);
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conceptos Kardex'),
        actions: [
          IconButton(
            key: const Key('conceptos_kardex_refrescar'),
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('conceptos_kardex_nuevo'),
        onPressed: _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in grouped.entries)
                  if (entry.value.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Rango ${entry.key}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          for (final it in entry.value)
                            ListTile(
                              key: Key('concepto_kardex_${it['id_concepto']}'),
                              leading: CircleAvatar(
                                backgroundColor: _colorRango(
                                  it['id_concepto'] ?? 0,
                                ).withValues(alpha: 0.1),
                                child: Icon(
                                  _iconoRango(it['id_concepto'] ?? 0),
                                  color: _colorRango(it['id_concepto'] ?? 0),
                                ),
                              ),
                              title: Text('${it['id_concepto']} - ${it['nombre']}'),
                              subtitle: Text(
                                '${it['signo']} · ${it['aplica_a']} · '
                                '${it['es_sistema'] == true ? 'Sistema' : 'Manual'} · '
                                '${it['activo'] == true ? 'Activo' : 'Inactivo'}',
                              ),
                              trailing: it['es_sistema'] == true
                                  ? null
                                  : IconButton(
                                      key: Key(
                                        'concepto_kardex_borrar_${it['id_concepto']}',
                                      ),
                                      tooltip: 'Eliminar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _borrar(it),
                                    ),
                              onTap: () => _editar(it),
                            ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
    );
  }
}
