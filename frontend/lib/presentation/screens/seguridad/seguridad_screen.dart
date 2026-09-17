import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/proxima_fase.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/user.dart';
import '../../../injection.dart' as di;

/// Mantenimiento: Seguridad y Accesos (roles/usuarios).
///
/// Presenta la matriz de roles del estándar (docs/MODELO_ESTANDAR.md) y
/// el rol del usuario actual. La gestión CRUD de usuarios se expone en la
/// próxima fase.
class SeguridadScreen extends StatefulWidget {
  const SeguridadScreen({super.key});

  @override
  State<SeguridadScreen> createState() => _SeguridadScreenState();
}

class _SeguridadScreenState extends State<SeguridadScreen> {
  User? _usuario;
  bool _cargando = true;

  static const _roles = [
    (
      'Administrador',
      'Configuración total del sistema, catálogos, usuarios, anulaciones y peso manual.',
      'ADMIN',
    ),
    (
      'Operador',
      'Entrada y salida de pesajes, impresión de tickets y registro de actividades.',
      'SUPERVISOR',
    ),
    (
      'Auditor',
      'Consulta de boletos, estatus y reportes. Sin acceso a anulaciones ni edición.',
      'AUDITOR',
    ),
    (
      'Trabajador',
      'Consulta básica de pesajes autorizados sin edición ni configuración.',
      'TRABAJADOR',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
  }

  Future<void> _cargarUsuario() async {
    final u = await di.sl<LocalStorage>().getCachedUser();
    if (mounted) {
      setState(() {
        _usuario = u;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad y Accesos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _rolSesion(context),
          const SizedBox(height: 14),
          for (final (nombre, descripcion, codigo) in _roles)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(Icons.lock_outline, size: 20),
                ),
                title: Text(nombre),
                subtitle: Text(descripcion),
                trailing: Text(
                  codigo,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SwsColors.gray500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          const ProximaFase(
            titulo: 'Gestión de usuarios y roles',
            icono: Icons.manage_accounts_outlined,
            descripcion:
                'Crear, editar y desactivar usuarios, asignar empresa y rol, '
                'y restablecer contraseñas. El backend expone JWT por rol '
                'desde el servidor; la administración visual se conectará '
                'aquí.',
            alcance: [
              'Alta/baja de usuarios por empresa y rol',
              'Restablecimiento de contraseñas (BCrypt)',
              'Matriz de permisos por pantalla y operativa',
            ],
          ),
        ],
      ),
    );
  }

  Widget _rolSesion(BuildContext context) {
    if (_cargando) {
      return const Card(child: ListTile(leading: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final u = _usuario;
    return Card(
      margin: EdgeInsets.zero,
      color: SwsColors.blue100,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined,
                color: SwsColors.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                u != null
                    ? 'Sesión actual: ${u.nombre} (${u.rol})'
                    : 'Inicia sesión para ver tu rol.',
                style: const TextStyle(fontSize: 13, color: SwsColors.gray700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}