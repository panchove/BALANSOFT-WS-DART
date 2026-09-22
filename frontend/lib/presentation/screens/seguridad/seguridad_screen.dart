import 'package:flutter/material.dart';

import '../../../core/constants/accesos_default.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/accesos_repository.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/user.dart';
import '../../../injection.dart' as di;

/// Mantenimiento: Seguridad y Accesos.
///
/// Muestra la matriz rol × módulo (alcances) y permite a ADMIN sobrescribir
/// el acceso de cada rol a cada módulo (`ver`, `editar` o `ninguno`). Los
/// cambios se persisten en el backend (`/api/v1/seguridad/matriz`) y, a
/// través de [AccesosRepository], el sidebar se refresca según el rol.
class SeguridadScreen extends StatefulWidget {
  const SeguridadScreen({super.key});

  @override
  State<SeguridadScreen> createState() => _SeguridadScreenState();
}

class _SeguridadScreenState extends State<SeguridadScreen> {
  AccesosRepository? _repo;
  User? _usuario;
  bool _cargando = true;
  bool _esAdmin = false;
  String? _mensaje;
  bool _esError = false;

  static const _roles = [
    ('Administrador', 'ADMIN'),
    ('Operador', 'OPERADOR'),
    ('Auditor', 'AUDITOR'),
    ('Trabajador', 'TRABAJADOR'),
  ];

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final repo = di.sl<AccesosRepository>();
    if (!repo.cargado) await repo.cargar();
    final u = await di.sl<LocalStorage>().getCachedUser();
    if (!mounted) return;
    setState(() {
      _repo = repo;
      _usuario = u;
      _esAdmin = u?.rol == 'ADMIN' || u?.isAdmin == true;
      _cargando = false;
    });
  }

  Future<void> _guardar(String rol, String modulo, String acceso) async {
    // El módulo de Seguridad debe quedar siempre accesible para ADMIN:
    // evitar cerrarse la puerta del propio sistema sin avisar.
    if (modulo == 'seguridad' && rol == 'ADMIN' && acceso == 'ninguno') {
      setState(() {
        _mensaje =
            'El rol ADMIN siempre conserva acceso a Seguridad y Accesos.';
        _esError = true;
      });
      return;
    }
    setState(() {
      _mensaje = null;
      _esError = false;
    });
    final ok = await _repo!.actualizar(rol, modulo, acceso);
    if (!mounted) return;
    setState(() {
      _mensaje = ok
          ? 'Acceso de $rol → $modulo actualizado.'
          : 'No se pudo guardar el acceso (sin conexión o permisos).';
      _esError = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad y Accesos')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _rolSesion(),
                const SizedBox(height: 12),
                if (_mensaje != null)
                  Card(
                    color: _esError
                        ? const Color(0xFFFdecea)
                        : const Color(0xFFE9f7ec),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _esError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: _esError ? SwsColors.danger : SwsColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _mensaje!,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (!_esAdmin)
                  const Card(
                    color: Color(0xFFFff4e5),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: SwsColors.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Modo solo lectura: solo el rol ADMIN puede '
                              'modificar los accesos.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _tablaMatriz(),
                const SizedBox(height: 16),
                _tarjetaRoles(),
                const SizedBox(height: 16),
                _cardLeyenda(),
              ],
            ),
    );
  }

  Widget _rolSesion() {
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

  /// Paleta local adaptada al tema (claro/oscuro).
  ({Color texto, Color textoSuave, Color borde, Color fondo}) _paleta() {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return (
      texto: oscuro ? SwsColors.darkText : SwsColors.dark,
      textoSuave: oscuro ? SwsColors.gray400 : SwsColors.gray600,
      borde: oscuro ? SwsColors.darkBorder : SwsColors.gray200,
      fondo: oscuro ? SwsColors.darkCard : SwsColors.light,
    );
  }

  Widget _tablaMatriz() {
    final repo = _repo!;
    final modulos = AccesosDefault.modulos.keys.toList();
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final textoSuave = oscuro ? SwsColors.darkText : SwsColors.gray600;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              'Matriz de accesos por rol',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Toca una celda para cambiar el nivel de acceso del rol al módulo.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ),
          // Encabezado de columnas (roles).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const SizedBox(width: 176),
                for (final (nombre, codigo) in _roles)
                  Expanded(
                    child: Tooltip(
                      message: nombre,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          _abreviarRol(nombre, codigo),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textoSuave,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final modulo in modulos)
            _filaModulo(repo, modulo),
        ],
      ),
    );
  }

  Widget _filaModulo(AccesosRepository repo, String modulo) {
    final titulo = AccesosDefault.modulos[modulo]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 176,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                children: [
                  Icon(AccesosDefault.iconoDe(modulo),
                      size: 18, color: SwsColors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final (_, codigo) in _roles)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _celdaAcceso(repo, rol: codigo, modulo: modulo),
              ),
            ),
        ],
      ),
    );
  }

  Widget _celdaAcceso(AccesosRepository repo, {required String rol, required String modulo}) {
    final acceso = repo.acceso(rol, modulo);
    // Blindaje de roles (REQ-REQ-NF-SERIE-03): las celdas del rol ADMIN nunca
    // se degradan en NINGÚN módulo. El resto de celdas solo las toca quien
    // NO es ADMIN (los demás roles los modifica el usuario con rol ADMIN).
    final esRolAdmin = rol == 'ADMIN';
    return _AccesoSegmentado(
      valor: acceso,
      habilitado: !esRolAdmin,
      alCambiar: !esRolAdmin ? _esAdmin ? (nuevo) => _guardar(rol, modulo, nuevo) : null : null,
    );
  }

  Widget _tarjetaRoles() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Roles de la estación',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final (nombre, descripcion, codigo) in _descripcionesRoles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 18, color: SwsColors.gray400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$codigo — $nombre: $descripcion',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardLeyenda() {
    final paleta = _paleta();
    return Card(
      margin: EdgeInsets.zero,
      color: paleta.fondo,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leyenda',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: paleta.texto)),
            const SizedBox(height: 6),
                       const _LeyendaFila(color: SwsColors.success, texto: 'Editar: acceso completo en el módulo.'),
            const SizedBox(height: 2),
            const _LeyendaFila(color: SwsColors.info, texto: 'Ver: solo lectura del módulo.'),
            const SizedBox(height: 2),
            _LeyendaFila(color: paleta.textoSuave, texto: 'Ninguno: módulo oculto para el rol.'),
            if (_esAdmin)
              const _LeyendaFila(
                color: SwsColors.warning,
                texto: 'Configuración bloqueada para ADMIN: el acceso'
                    ' "editar" no se puede revocar.',
              ),
          ],
        ),
      ),
    );
  }

  static const _descripcionesRoles = [
    ('Administrador', 'configuración total del sistema, catálogos, usuarios, anulaciones y peso manual', 'ADMIN'),
    ('Operador', 'entrada y salida de pesajes, catálogos operativos e impresión de tickets', 'OPERADOR'),
    ('Auditor', 'consulta de boletos, catálogos y reportes; sin edición', 'AUDITOR'),
    ('Trabajador', 'consulta básica de inicio autorizada', 'TRABAJADOR'),
  ];

  static String _abreviarRol(String nombre, String codigo) {
    return switch (codigo) {
      'ADMIN' => 'Admin',
      'OPERADOR' => 'Operador',
      'AUDITOR' => 'Auditor',
      'TRABAJADOR' => 'Trabajador',
      _ => codigo,
    };
  }
}

/// Control de tres estados (`ninguno` / `ver` / `editar`).
class _AccesoSegmentado extends StatelessWidget {
  final String valor;
  final bool habilitado;
  final ValueChanged<String>? alCambiar;

  const _AccesoSegmentado({
    required this.valor,
    required this.habilitado,
    this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final destacado = Theme.of(context).colorScheme.surfaceContainerHighest;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
                onTap: !habilitado
                    ? null
                    : () => _mostrarSelector(context),
                child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: habilitado ? SwsColors.light : destacado,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SwsColors.gray200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _circuloAcceso(valor),
            const SizedBox(width: 5),
            Text(
              _labelAcceso(valor),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circuloAcceso(String acceso) {
    final color = switch (acceso) {
      'editar' => SwsColors.success,
      'ver' => SwsColors.info,
      _ => SwsColors.gray400,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _labelAcceso(String acceso) {
    return switch (acceso) {
      'editar' => 'Editar',
      'ver' => 'Ver',
      _ => 'Ninguno',
    };
  }

  Future<void> _mostrarSelector(BuildContext context) async {
    final eleccion = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Nivel de acceso'),
        children: [
          for (final (valor, label, color) in const [
            ('ninguno', 'Ninguno (oculto)', SwsColors.gray400),
            ('ver', 'Ver (solo lectura)', SwsColors.info),
            ('editar', 'Editar (lectura y escritura)', SwsColors.success),
          ])
            ListTile(
              leading: Icon(Icons.circle, color: color, size: 16),
              title: Text(label),
              selected: valor == this.valor,
              onTap: () => Navigator.of(ctx).pop(valor),
            ),
        ],
      ),
    );
    if (eleccion != null && eleccion != valor) {
      alCambiar?.call(eleccion);
    }
  }
}

class _LeyendaFila extends StatelessWidget {
  final Color color;
  final String texto;

  const _LeyendaFila({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}