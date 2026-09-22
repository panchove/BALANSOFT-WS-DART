import 'package:flutter/material.dart';

import '../../../presentation/widgets/atajo_nuevo.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

/// Gestión de usuarios locales (solo ADMIN). Crea/modifica operadores y los
/// encola en `sync_queue` para entregarlos al panel (credenciales).
///
/// Protección de la cuenta ADMIN (REQ-FN-USR): el administrador principal no
/// puede desactivarse ni degradarse, y su contraseña/correo no pueden cambiar.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  static const _roles = ['OPERADOR', 'ADMIN', 'AUDITOR', 'TRABAJADOR'];

  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await di.sl<ApiClient>().listUsuarios();
      if (!mounted) return;
      setState(() {
        _usuarios =
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los usuarios: $e';
      });
    }
  }

  bool _esAdmin(Map<String, dynamic>? usuario) =>
      usuario != null && usuario['rol'] == 'ADMIN';

  Future<void> _mostrarFormulario([Map<String, dynamic>? usuario]) async {
    final esAdmin = _esAdmin(usuario);
    final bloqueoCredenciales = esAdmin;

    final nombreCtrl = TextEditingController(text: usuario?['nombre'] ?? '');
    final emailCtrl = TextEditingController(text: usuario?['email'] ?? '');
    final passCtrl = TextEditingController();
    var rol = (usuario?['rol'] as String?) ?? 'OPERADOR';

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(usuario == null ? 'Nuevo usuario' : 'Editar usuario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  enabled: !bloqueoCredenciales,
                  decoration: InputDecoration(
                    labelText: 'Nombre',
                    helperText: bloqueoCredenciales
                        ? 'Cuenta con credenciales asignadas por el panel'
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  enabled: usuario == null,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: rol,
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    helperText: bloqueoCredenciales
                        ? 'El rol del administrador no puede degradarse'
                        : null,
                  ),
                  items: _roles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: bloqueoCredenciales
                      ? null
                      : (v) => setDialogState(() {
                          if (v != null) rol = v;
                        }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  enabled: !bloqueoCredenciales,
                  decoration: InputDecoration(
                    labelText: bloqueoCredenciales
                        ? 'Contraseña asignada por el panel'
                        : usuario == null
                            ? 'Contraseña (mín. 6)'
                            : 'Nueva contraseña (vacío = mantener)',
                    helperText: bloqueoCredenciales
                        ? 'Usa la contraseña enviada por Balansoft'
                        : null,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado != true || !mounted) return;
    final nombre = nombreCtrl.text.trim();
    final email = emailCtrl.text.trim();
    if (nombre.length < 3 || usuario == null && email.isEmpty) {
      _snack('Datos incompletos', error: true);
      return;
    }
    try {
      final body = <String, dynamic>{
        'nombre': nombre,
        'rol': rol,
        if (usuario == null) 'email': email,
        if (passCtrl.text.isNotEmpty && !esAdmin) 'password': passCtrl.text,
      };
      if (usuario == null) {
        await di.sl<ApiClient>().createUsuario(body);
      } else {
        await di.sl<ApiClient>()
            .updateUsuario('${usuario['id_usuario']}', body);
      }
      await _cargar();
      _snack(usuario == null ? 'Usuario creado y encolado' : 'Usuario actualizado');
    } catch (e) {
      _snack('Error al guardar: $e', error: true);
    }
  }

  Future<void> _toggleActivo(Map<String, dynamic> usuario, bool activo) async {
    if (!activo && usuario['rol'] == 'ADMIN') {
      _snack('No se puede desactivar una cuenta ADMIN', error: true);
      return;
    }
    try {
      await di.sl<ApiClient>().updateUsuario('${usuario['id_usuario']}', {
        'activo': activo,
      });
      await _cargar();
      _snack(activo ? 'Usuario activado' : 'Usuario desactivado');
    } catch (e) {
      _snack('Error al actualizar: $e', error: true);
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
    return AtajoNuevo(
      onNuevo: () => _mostrarFormulario(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Usuarios y roles')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _mostrarFormulario(),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Nuevo'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    if (_usuarios.isEmpty) {
      return const Center(child: Text('No hay usuarios. Crea el primero.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _usuarios.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final u = _usuarios[i];
          final activo = u['activo'] == true;
          final esAdmin = u['rol'] == 'ADMIN';
          final rolLabel = esAdmin ? 'ADMIN (protegido)' : '${u['rol']}';
          return ListTile(
            leading: CircleAvatar(
              child: Text((u['nombre'] as String? ?? '?').characters.first),
            ),
            title: Text(
              '${u['nombre']}',
              style: const TextStyle(overflow: TextOverflow.ellipsis),
            ),
            subtitle: Text(
              '${u['email']} · $rolLabel',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Tooltip(
              message: esAdmin
                  ? 'La cuenta ADMIN no puede desactivarse'
                  : activo
                      ? 'Activo (toca para desactivar)'
                      : 'Inactivo (toca para activar)',
              child: Switch(
                value: activo,
                onChanged: esAdmin
                    ? null
                    : (v) => _toggleActivo(u, v),
              ),
            ),
            onTap: () => _mostrarFormulario(u),
          );
        },
      ),
    );
  }
}
