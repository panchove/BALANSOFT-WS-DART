import 'package:flutter/material.dart';

import '../../../core/constants/accesos_default.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import '../seguridad/seguridad_screen.dart';

/// Mantenimiento: ROLES.
///
/// Catálogo de los roles locales de la estación (ADMIN / OPERADOR / AUDITOR).
/// El rol efectivo lo determina la matriz de accesos, así que esta pantalla es
/// informativa y enlaza a *Seguridad y Accesos* para editar los alcances. No se
/// pueden crear roles nuevos: `usuarios.rol` tiene un CHECK en la BD y la
/// matriz de módulos vive en `app/core/seguridad_matrix.py`.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<Map<String, dynamic>>? _roles;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _roles = null;
      _error = null;
    });
    try {
      final roles = await di.sl<ApiClient>().listarRoles();
      if (!mounted) return;
      setState(() => _roles = roles);
    } catch (e) {
      if (!mounted) return;
      // Respaldo offline: la descripción local de los roles siempre está
      // disponible, aunque el conteo de usuarios no.
      setState(() {
        _error = e.toString();
        _roles = _respaldoLocal();
      });
    }
  }

  /// Roles con la información que vive en el cliente (sin conteo de usuarios).
  List<Map<String, dynamic>> _respaldoLocal() {
    return [
      for (final clave in AccesosDefault.roles)
        {
          'clave': clave,
          'nombre': _tituloRol(clave),
          'descripcion': _descripcionRol(clave),
          'usuarios': null,
        },
    ];
  }

  static String _tituloRol(String clave) {
    return switch (clave) {
      'ADMIN' => 'Administrador',
      'OPERADOR' => 'Operador',
      'AUDITOR' => 'Auditor',
      _ => clave,
    };
  }

  static String _descripcionRol(String clave) {
    return switch (clave) {
      'ADMIN' => 'Control total de la estación: configuración, usuarios, '
          'dispositivos y todos los módulos en modo edición.',
      'OPERADOR' => 'Operación diaria de pesaje y catálogos. Sin acceso a '
          'configuración, dispositivos ni seguridad.',
      'AUDITOR' => 'Consulta y fiscalización: ve los módulos operativos en '
          'solo lectura y la auditoría del sistema.',
      _ => '',
    };
  }

  IconData _iconoRol(String clave) {
    return switch (clave) {
      'ADMIN' => Icons.admin_panel_settings_outlined,
      'OPERADOR' => Icons.badge_outlined,
      'AUDITOR' => Icons.fact_check_outlined,
      _ => Icons.person_outline,
    };
  }

  Color _colorRol(String clave) {
    return switch (clave) {
      'ADMIN' => SwsColors.primary,
      'OPERADOR' => SwsColors.success,
      'AUDITOR' => SwsColors.info,
      _ => SwsColors.gray500,
    };
  }

  void _abrirMatriz() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SeguridadScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        actions: [
          IconButton(
            tooltip: 'Ver matriz de accesos',
            icon: const Icon(Icons.grid_on_outlined),
            onPressed: _abrirMatriz,
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _roles == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  const Card(
                    color: Color(0xFFFFF4E5),
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              color: SwsColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sin conexión con la API: se muestra la '
                              'descripción local de los roles.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Card(
                  margin: EdgeInsets.only(bottom: 12),
                  color: SwsColors.blue100,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: SwsColors.primary, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Los roles de la estación son fijos. Su alcance '
                            'por módulo se ajusta en Seguridad y Accesos.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final rol in _roles!) _tarjetaRol(rol),
              ],
            ),
    );
  }

  Widget _tarjetaRol(Map<String, dynamic> rol) {
    final clave = '${rol['clave'] ?? ''}';
    final color = _colorRol(clave);
    final usuarios = rol['usuarios'];
    final editar = rol['modulos_editar'];
    final ver = rol['modulos_ver'];
    final ninguno = rol['modulos_ninguno'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconoRol(clave), color: color, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${rol['nombre'] ?? _tituloRol(clave)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        clave,
                        style: const TextStyle(
                            fontSize: 12, color: SwsColors.gray500),
                      ),
                    ],
                  ),
                ),
                if (usuarios is num)
                  Chip(
                    avatar: const Icon(Icons.people_outline, size: 16),
                    label: Text(
                      usuarios == 1 ? '1 usuario' : '$usuarios usuarios',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${rol['descripcion'] ?? _descripcionRol(clave)}',
              style: const TextStyle(fontSize: 13),
            ),
            if (editar is num && ver is num && ninguno is num) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _badge('$editar editar', SwsColors.success),
                  _badge('$ver ver', SwsColors.info),
                  _badge('$ninguno sin acceso', SwsColors.gray500),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
