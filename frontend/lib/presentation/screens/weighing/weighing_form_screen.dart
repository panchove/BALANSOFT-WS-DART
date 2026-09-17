import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/forms/autocomplete_creatable.dart';
import '../../../core/widgets/forms/create_item_dialog.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../data/services/scale_api_client.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/entities/weighing.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/catalog/catalog_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';

const _specCamion = CreatableSpec<Camion>(
  path: ApiConstants.camiones,
  titulo: 'Nuevo Camión',
  icon: Icons.directions_car,
  parse: Camion.fromJson,
  campos: [
    CrearCampoSpec(key: 'placa', label: 'Placa', icon: Icons.tag_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'color', label: 'Color', icon: Icons.palette_outlined),
    CrearCampoSpec(key: 'tara_habitual', label: 'Tara habitual (kg)', icon: Icons.fitness_center, tipo: CrearCampoTipo.numero),
  ],
);

const _specRemolque = CreatableSpec<Trailer>(
  path: ApiConstants.remolques,
  titulo: 'Nuevo Remolque',
  icon: Icons.local_shipping_outlined,
  parse: Trailer.fromJson,
  campos: [
    CrearCampoSpec(key: 'placa', label: 'Placa', icon: Icons.tag_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'tipo_remolque', label: 'Tipo de remolque', icon: Icons.category_outlined),
    CrearCampoSpec(key: 'tara_habitual', label: 'Tara habitual (kg)', icon: Icons.fitness_center, tipo: CrearCampoTipo.numero),
  ],
);

const _specTransporte = CreatableSpec<Transport>(
  path: ApiConstants.transportes,
  titulo: 'Nuevo Transporte',
  icon: Icons.fire_truck_outlined,
  parse: Transport.fromJson,
  campos: [
    CrearCampoSpec(key: 'razon_social', label: 'Razón social', icon: Icons.badge_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(key: 'identificacion_fiscal', label: 'RIF / Identificación fiscal', icon: Icons.badge_outlined),
    CrearCampoSpec(key: 'contacto', label: 'Contacto', icon: Icons.person_outline),
    CrearCampoSpec(key: 'telefono', label: 'Teléfono', icon: Icons.phone_outlined),
  ],
);

const _specProducto = CreatableSpec<Product>(
  path: ApiConstants.productos,
  titulo: 'Nuevo Producto',
  icon: Icons.inventory,
  parse: Product.fromJson,
  campos: [
    CrearCampoSpec(key: 'nombre', label: 'Nombre', icon: Icons.badge_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(key: 'densidad_estandar', label: 'Densidad estándar', icon: Icons.speed_outlined, tipo: CrearCampoTipo.numero),
    CrearCampoSpec(key: 'unidad_medida', label: 'Unidad de medida', icon: Icons.straighten_outlined, tipo: CrearCampoTipo.dropdown, opciones: ['TON', 'KG', 'LBS', 'UN']),
    CrearCampoSpec(key: 'es_kardex', label: 'Generar movimiento de kardex', icon: Icons.book_outlined, tipo: CrearCampoTipo.booleano),
  ],
);

const _specAlmacen = CreatableSpec<Warehouse>(
  path: ApiConstants.almacenes,
  titulo: 'Nuevo Almacén',
  icon: Icons.warehouse,
  parse: Warehouse.fromJson,
  campos: [
    CrearCampoSpec(key: 'nombre', label: 'Nombre', icon: Icons.badge_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(key: 'ubicacion', label: 'Ubicación', icon: Icons.place_outlined),
  ],
);

const _specBalanza = CreatableSpec<Scale>(
  path: ApiConstants.balanzas,
  titulo: 'Nueva Balanza',
  icon: Icons.scale,
  parse: Scale.fromJson,
  campos: [
    CrearCampoSpec(key: 'descripcion', label: 'Descripción', icon: Icons.badge_outlined, requerido: true, precargarTexto: true),
    CrearCampoSpec(key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(key: 'marca', label: 'Marca', icon: Icons.local_offer_outlined),
    CrearCampoSpec(key: 'modelo', label: 'Modelo', icon: Icons.model_training),
  ],
);

class WeighingFormScreen extends StatelessWidget {
  const WeighingFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CatalogBloc>(
      create: (_) => di.sl<CatalogBloc>()..add(const FetchCatalogsEvent()),
      child: Scaffold(
        appBar: _WeighingFormAppBar(),
        body: const _WeighingFormBody(),
      ),
    );
  }
}

class _WeighingFormAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      title: const Text('Estación de Pesaje', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      actions: [
        _ActionChip(
          icon: Icons.search,
          label: 'Buscar',
          shortcut: 'F3',
          onTap: () => _abrirBusqueda(context),
        ),
        const SizedBox(width: 4),
        _ActionChip(
          icon: Icons.print_outlined,
          label: 'Imprimir',
          shortcut: 'F5',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione un boleto para imprimir')),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _abrirBusqueda(BuildContext context) {
    Navigator.of(context, rootNavigator: true)
        .pushReplacementNamed('/dashboard', arguments: 'entradas');
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onTap;

  const _ActionChip({required this.icon, required this.label, this.shortcut, this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontSize: 12.5,
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  shortcut!,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeighingFormBody extends StatefulWidget {
  const _WeighingFormBody();

  @override
  State<_WeighingFormBody> createState() => _WeighingFormBodyState();
}

class _WeighingFormBodyState extends State<_WeighingFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _scaleClient = di.sl<ScaleApiClient>();
  final _scrollController = ScrollController();

  // ── Índices de los campos (orden de navegación con flechas) ─────────────
  // Autocompletes + dropdown de DATOS DEL PESAJE
  static const int _idxCamion = 0;
  static const int _idxRemolque = 1;
  static const int _idxTransporte = 2;
  static const int _idxConductor = 3;
  static const int _idxProducto = 4;
  static const int _idxAlmacen = 5;
  static const int _idxBalanza = 6;
  static const int _idxTipoTercero = 7;
  static const int _idxTercero = 8;
  // Campos de texto (LECTURA DE PESOS + DATOS ADICIONALES + OBSERVACIONES)
  static const int _idxPesoEntrada = 9;
  static const int _idxPesoRemolque = 10;
  static const int _idxDocumento = 11;
  static const int _idxGuiaSunagro = 12;
  static const int _idxMedida = 13;
  static const int _idxUnidades = 14;
  static const int _idxDensidad = 15;
  static const int _idxFlete = 16;
  static const int _idxCostoFlete = 17;
  static const int _idxObservaciones = 18;

  static const int _totalCampos = 19;

  final List<FocusNode?> _focos = List.filled(_totalCampos, null);
  final List<bool> _confirmados = List.filled(_totalCampos, false);

  // FocusNodes propios (dropdown + campos de texto).
  final _tipoTerceroFocus = FocusNode();
  final _pesoEntradaFocus = FocusNode();
  final _pesoRemolqueFocus = FocusNode();
  final _documentoFocus = FocusNode();
  final _guiaSunagroFocus = FocusNode();
  final _medidaFocus = FocusNode();
  final _unidadesFocus = FocusNode();
  final _densidadFocus = FocusNode();
  final _fleteFocus = FocusNode();
  final _costoFleteFocus = FocusNode();
  final _observacionesFocus = FocusNode();

  final _pesoEntradaCtrl = TextEditingController();
  final _pesoRemolqueCtrl = TextEditingController();
  final _pesoNetoDeclaradoCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();
  final _guiaSunagroCtrl = TextEditingController();
  final _medidaCtrl = TextEditingController();
  final _unidadesCtrl = TextEditingController();
  final _densidadCtrl = TextEditingController();
  final _fleteCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  bool _remolque = false;
  String _tipoTercero = 'CLIENTE';
  bool _esPesoManual = false;
  bool _puedePesoManual = false;
  bool _hayBascula = false; // hay básculas registradas en dispositivos
  List<PhotoCaptured> _fotosCamion = [];
  List<PhotoCaptured> _fotosRemolque = [];

  Camion? _camionSeleccionado;
  Trailer? _remolqueSeleccionado;
  Transport? _transporteSeleccionado;
  Driver? _conductorSeleccionado;
  Product? _productoSeleccionado;
  Warehouse? _almacenSeleccionado;
  Scale? _balanzaSeleccionada;
  ThirdParty? _terceroSeleccionado;
  String _camionTexto = '';
  String _remolqueTexto = '';
  String _transporteTexto = '';
  String _conductorTexto = '';
  String _productoTexto = '';
  String _almacenTexto = '';
  String _balanzaTexto = '';
  String _terceroTexto = '';

  final Map<String, List<Object>> _nuevos = {};
  String? _numeroBoleto;
  DateTime? _fechaActual;

  @override
  void initState() {
    super.initState();
    _fechaActual = DateTime.now();
    // Registrar los FocusNode de los campos que no exponen `onFocusNodeReady`.
    _focos[_idxTipoTercero] = _tipoTerceroFocus;
    _focos[_idxPesoEntrada] = _pesoEntradaFocus;
    _focos[_idxPesoRemolque] = _pesoRemolqueFocus;
    _focos[_idxDocumento] = _documentoFocus;
    _focos[_idxGuiaSunagro] = _guiaSunagroFocus;
    _focos[_idxMedida] = _medidaFocus;
    _focos[_idxUnidades] = _unidadesFocus;
    _focos[_idxDensidad] = _densidadFocus;
    _focos[_idxFlete] = _fleteFocus;
    _focos[_idxCostoFlete] = _costoFleteFocus;
    _focos[_idxObservaciones] = _observacionesFocus;
    _cargarPermisosYEstado();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    _scrollController.dispose();
    _tipoTerceroFocus.dispose();
    _pesoEntradaFocus.dispose();
    _pesoRemolqueFocus.dispose();
    _documentoFocus.dispose();
    _guiaSunagroFocus.dispose();
    _medidaFocus.dispose();
    _unidadesFocus.dispose();
    _densidadFocus.dispose();
    _fleteFocus.dispose();
    _costoFleteFocus.dispose();
    _observacionesFocus.dispose();
    _pesoEntradaCtrl.dispose();
    _pesoRemolqueCtrl.dispose();
    _pesoNetoDeclaradoCtrl.dispose();
    _documentoCtrl.dispose();
    _guiaSunagroCtrl.dispose();
    _medidaCtrl.dispose();
    _unidadesCtrl.dispose();
    _densidadCtrl.dispose();
    _fleteCtrl.dispose();
    _costoFleteCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  // ─── Permisos y estado de báscula ──────────────────────────────────────
  Future<void> _cargarPermisosYEstado() async {
    final user = await di.sl<LocalStorage>().getCachedUser();
    bool hayBascula = false;
    try {
      final api = di.sl<ApiClient>();
      final res = await api.getList(ApiConstants.balanzas);
      final data = res.data;
      hayBascula = data is List && data.isNotEmpty;
    } catch (_) {
      hayBascula = false;
    }
    if (!mounted) return;
    setState(() {
      _puedePesoManual = user?.rol == 'ADMIN' || user?.rol == 'SUPERVISOR';
      _hayBascula = hayBascula;
      _esPesoManual = !hayBascula;
    });
  }

  // ─── Atajos de teclado ────────────────────────────────────────────────
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f2) {
      _registrarEntrada();
      return true;
    }
    if (key == LogicalKeyboardKey.f3) {
      _limpiarFormulario();
      return true;
    }
    if (key == LogicalKeyboardKey.f4) {
      _onSave();
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      _imprimirActual();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent &&
        !_estaEnInput() &&
        !_hayDialogAbierto()) {
      _onSave();
      return true;
    }
    return false;
  }

  bool _estaEnInput() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _hayDialogAbierto() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ModalRoute.of(ctx) is PopupRoute;
  }

  void _confirmarCampo(int idx) {
    _confirmados[idx] = true;
  }

  void _desconfirmarCampo(int idx) {
    _confirmados[idx] = false;
  }

  /// Orden efectivo de los campos según la configuración actual:
  /// Camión → (Remolque) → Transporte → Conductor → Producto → Almacén →
  /// Balanza → TipoTercero → Tercero → PesoEntrada → (PesoRemolque) →
  /// Documento → GuíaSUNAGRO → Medida → Unidades → Densidad → Flete →
  /// CostoFlete → Observaciones.
  List<int> _ordenEfectivo() {
    return <int>[
      _idxCamion,
      if (_remolque) _idxRemolque,
      _idxTransporte,
      _idxConductor,
      _idxProducto,
      _idxAlmacen,
      _idxBalanza,
      _idxTipoTercero,
      _idxTercero,
      _idxPesoEntrada,
      if (_remolque) _idxPesoRemolque,
      _idxDocumento,
      _idxGuiaSunagro,
      _idxMedida,
      _idxUnidades,
      _idxDensidad,
      _idxFlete,
      _idxCostoFlete,
      _idxObservaciones,
    ];
  }

  /// Navegación con flechas:
  /// - ← / → : campo anterior/siguiente SOLO si el campo enfocado ya quedó
  ///   confirmado con Enter. Si no, se deja pasar al campo para mover cursor.
  /// - ↑ / ↓ : NUNCA se interceptan aquí.
  KeyEventResult _manejarFlechas(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowLeft => -1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final idx = _focos.indexWhere((f) => f?.hasFocus == true);
    if (idx < 0 || !_confirmados[idx]) return KeyEventResult.ignored;
    _moverFocoDesde(idx, delta);
    return KeyEventResult.handled;
  }

  void _moverFocoDesde(int actual, int delta) {
    final visibles = [
      for (final i in _ordenEfectivo())
        if (_focos[i] != null) i,
    ];
    final pos = visibles.indexOf(actual);
    if (pos < 0) return;
    final nuevo = (pos + delta).clamp(0, visibles.length - 1);
    if (nuevo != pos) _focos[visibles[nuevo]]?.requestFocus();
  }

  /// Avanza al siguiente campo visible tras confirmar con Enter.
  /// Si es el último (Observaciones), hace unfocus.
  void _avanzarAlSiguienteCampo(int actual) {
    final visibles = [
      for (final i in _ordenEfectivo())
        if (_focos[i] != null) i,
    ];
    final pos = visibles.indexOf(actual);
    if (pos < 0) return;
    if (pos >= visibles.length - 1) {
      FocusScope.of(context).unfocus();
      return;
    }
    _focos[visibles[pos + 1]]?.requestFocus();
  }

  void _registrarNuevo(String tipo, Object item) {
    setState(() {
      (_nuevos[tipo] ??= []).add(item);
    });
  }

  List<T> _unidos<T>(String tipo, List<T> base) =>
      [...base, ...(_nuevos[tipo] ?? const []).cast<T>()];

  bool _pareceCedula(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^(V|E|J|G|P)?-?\d{3,}$').hasMatch(t);
  }

  void _onRemolqueSeleccionado(Trailer? trailer) {
    setState(() {
      _remolqueSeleccionado = trailer;
      if (trailer != null) _confirmados[_idxRemolque] = true;
      if (trailer != null && _pesoRemolqueCtrl.text.trim().isEmpty) {
        _pesoRemolqueCtrl.text = trailer.taraHabitual?.toStringAsFixed(2) ?? '';
      }
    });
  }

  // --- Cálculos MODEL.md ---
  double get _pesoTotalEntrada =>
      (double.tryParse(_pesoEntradaCtrl.text) ?? 0) +
      (double.tryParse(_pesoRemolqueCtrl.text) ?? 0);

  double get _pesoNetoDeclarado => double.tryParse(_pesoNetoDeclaradoCtrl.text) ?? 0;

  double get _pesoDiferencia {
    final pnd = _pesoNetoDeclarado;
    if (pnd == 0) return 0;
    return _pesoNetoTotal - pnd;
  }

  double get _pesoNetoTotal => _pesoTotalEntrada;

  double get _porcentajeDesviacion {
    final pnd = _pesoNetoDeclarado;
    if (pnd == 0) return 0;
    return (_pesoDiferencia / pnd) * 100;
  }

  void _registrarEntrada() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Modo Entrada — capture el peso y guarde'),
        backgroundColor: SwsColors.accent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _limpiarFormulario() {
    setState(() {
      _pesoEntradaCtrl.clear();
      _pesoRemolqueCtrl.clear();
      _pesoNetoDeclaradoCtrl.clear();
      _documentoCtrl.clear();
      _guiaSunagroCtrl.clear();
      _medidaCtrl.clear();
      _unidadesCtrl.clear();
      _densidadCtrl.clear();
      _fleteCtrl.clear();
      _costoFleteCtrl.clear();
      _observacionesCtrl.clear();
      _camionSeleccionado = null;
      _remolqueSeleccionado = null;
      _transporteSeleccionado = null;
      _conductorSeleccionado = null;
      _productoSeleccionado = null;
      _almacenSeleccionado = null;
      _balanzaSeleccionada = null;
      _terceroSeleccionado = null;
      _camionTexto = '';
      _remolqueTexto = '';
      _transporteTexto = '';
      _conductorTexto = '';
      _productoTexto = '';
      _almacenTexto = '';
      _balanzaTexto = '';
      _terceroTexto = '';
      _remolque = false;
      _esPesoManual = !_hayBascula;
      _fotosCamion = [];
      _fotosRemolque = [];
      _numeroBoleto = null;
      _fechaActual = DateTime.now();
      for (var i = 0; i < _confirmados.length; i++) {
        _confirmados[i] = false;
      }
    });
  }

  void _imprimirActual() {
    if (_numeroBoleto != null) {
      _reimprimirTicket(_numeroBoleto!, _numeroBoleto!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guarde el pesaje primero para imprimir')),
      );
    }
  }

  Future<void> _reimprimirTicket(String boleto, String nombreBoleto) async {
    try {
      final response = await di.sl<WeighingRepository>().getTicketPdf(boleto);
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un PDF válido.');
      }
      final ruta = await SaveFileUtils.save(bytes, 'ticket_$nombreBoleto.pdf', subcarpeta: 'tickets');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket guardado en: $ruta'), backgroundColor: SwsColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar ticket: $e'), backgroundColor: SwsColors.danger),
        );
      }
    }
  }

  void _onSave() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete los campos mínimos para guardar'),
          backgroundColor: SwsColors.warning,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final placa = _camionSeleccionado?.placa ?? _camionTexto.toUpperCase();

    final weighing = Weighing(
      boleto: '',
      idVehiculo: placa.isEmpty ? null : placa,
      remolque: _remolque,
      idRemolque: _remolque ? _remolqueSeleccionado?.id : null,
      idTransporte: _transporteSeleccionado?.id,
      idConductor: _conductorSeleccionado?.cedulaDni,
      idProducto: _productoSeleccionado?.id,
      idAlmacen: _almacenSeleccionado?.id,
      idBalanza: _balanzaSeleccionada?.id,
      tipoTercero: _terceroSeleccionado != null ? _tipoTercero : null,
      idTercero: _terceroSeleccionado?.id,
      fechaHoraEntrada: now,
      pesoEntradaVehiculo: double.tryParse(_pesoEntradaCtrl.text) ?? 0,
      pesoEntradaRemolque: _remolque ? double.tryParse(_pesoRemolqueCtrl.text) : null,
      pesoNetoDeclarado: _pesoNetoDeclaradoCtrl.text.isNotEmpty ? double.tryParse(_pesoNetoDeclaradoCtrl.text) : null,
      documento: _documentoCtrl.text.trim().isNotEmpty ? _documentoCtrl.text.trim() : null,
      flete: _fleteCtrl.text.trim().isNotEmpty ? _fleteCtrl.text.trim() : null,
      costoFlete: double.tryParse(_costoFleteCtrl.text),
      densidad: double.tryParse(_densidadCtrl.text),
      litros: double.tryParse(_unidadesCtrl.text),
      observaciones: _observacionesCtrl.text.trim().isNotEmpty ? _observacionesCtrl.text.trim() : null,
      createdAt: now,
      updatedAt: now,
    );

    final adicionales = <String, dynamic>{
      'remolque_placa': _remolque ? (_remolqueSeleccionado?.placa ?? _remolqueTexto) : null,
      'transporte_nombre': _transporteSeleccionado?.razonSocial ?? _transporteTexto,
      'conductor_nombre': _conductorTexto,
      'producto_nombre': _productoSeleccionado?.nombre ?? _productoTexto,
      'almacen_nombre': _almacenSeleccionado?.nombre ?? _almacenTexto,
      'balanza_nombre': _balanzaSeleccionada?.descripcion ?? _balanzaTexto,
      'tercero_nombre': _terceroSeleccionado?.razonSocial ?? _terceroTexto,
      'es_peso_manual': _esPesoManual,
      'guia_sunagro': _guiaSunagroCtrl.text.trim().isNotEmpty ? _guiaSunagroCtrl.text.trim() : null,
      'medida': _medidaCtrl.text.trim().isNotEmpty ? _medidaCtrl.text.trim() : null,
    };

    context.read<WeighingBloc>().add(CreateWeighingEvent(weighing, adicionales: adicionales));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WeighingBloc, WeighingState>(
      listener: (context, state) {
        if (state is WeighingCreated) {
          final boleto = state.weighing.boleto;
          _numeroBoleto = boleto;
          _subirFotos(boleto);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pesaje #$boleto creado — F5 para imprimir'),
              backgroundColor: SwsColors.success,
              action: SnackBarAction(
                label: 'IMPRIMIR',
                textColor: Colors.white,
                onPressed: () => _reimprimirTicket(boleto, state.weighing.numeroBoleto ?? boleto),
              ),
            ),
          );
        } else if (state is WeighingError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: SwsColors.danger),
          );
        }
      },
      child: BlocBuilder<CatalogBloc, CatalogState>(
        builder: (context, state) {
          if (state is CatalogLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = state is CatalogLoaded ? state.data : CatalogData.empty;
          return _buildForm(context, data);
        },
      ),
    );
  }

  Future<void> _subirFotos(String boleto) async {
    if (boleto.isEmpty) return;
    final api = di.sl<ApiClient>();
    final camion = _fotosCamion.map((f) => (foto: f, tipo: 'vehiculo'));
    final remolque = _fotosRemolque.map((f) => (foto: f, tipo: 'otros'));
    final todas = [...camion, ...remolque];
    if (todas.isEmpty) return;
    try {
      for (final entrada in todas) {
        await api.uploadImage(boleto, entrada.foto.bytes, entrada.foto.nombre, tipo: entrada.tipo);
      }
    } catch (_) {}
  }

  Widget _buildForm(BuildContext context, CatalogData data) {
    final trailers = data.trailersActivos;
    final terceros = data.tercerosPorTipo(_tipoTercero);
    final isWide = MediaQuery.sizeOf(context).width > 900;

    return Column(
      children: [
        _QuickActionBar(
          onEntrada: _registrarEntrada,
          onGuardar: _onSave,
          onCancelar: _limpiarFormulario,
          onImprimir: _imprimirActual,
          onSalir: () => Navigator.of(context).pop(),
          puedeAnular: false,
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Form(
              key: _formKey,
              child: Focus(
                onKeyEvent: _manejarFlechas,
                child: isWide
                    ? _buildTwoColumnLayout(context, data, trailers, terceros)
                    : _buildSingleColumnLayout(context, data, trailers, terceros),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTwoColumnLayout(BuildContext context, CatalogData data, List<Trailer> trailers, List<ThirdParty> terceros) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'DATOS DEL PESAJE',
                icon: Icons.assignment,
                children: _buildDatosSection(context, data, trailers, terceros),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'LECTURA DE PESOS',
                icon: Icons.monitor_weight,
                children: _buildLecturaSection(context),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'DATOS ADICIONALES',
                icon: Icons.description,
                children: _buildAdicionalesSection(context),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'OBSERVACIONES',
                icon: Icons.notes,
                children: _buildObservacionesSection(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: Column(
            children: [
              _SectionCard(
                title: 'RESUMEN',
                icon: Icons.summarize,
                children: _buildResumenSection(data),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'FOTOS',
                icon: Icons.photo_camera,
                children: _buildFotosSection(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(BuildContext context, CatalogData data, List<Trailer> trailers, List<ThirdParty> terceros) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'DATOS DEL PESAJE',
          icon: Icons.assignment,
          children: _buildDatosSection(context, data, trailers, terceros),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'LECTURA DE PESOS',
          icon: Icons.monitor_weight,
          children: _buildLecturaSection(context),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'DATOS ADICIONALES',
          icon: Icons.description,
          children: _buildAdicionalesSection(context),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'OBSERVACIONES',
          icon: Icons.notes,
          children: _buildObservacionesSection(),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'RESUMEN',
          icon: Icons.summarize,
          children: _buildResumenSection(data),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'FOTOS',
          icon: Icons.photo_camera,
          children: _buildFotosSection(),
        ),
      ],
    );
  }

  List<Widget> _buildDatosSection(BuildContext context, CatalogData data, List<Trailer> trailers, List<ThirdParty> terceros) {
    return [
      _HeaderInfoRow(
        label: 'Serie - Boleto',
        value: _numeroBoleto ?? 'PENDIENTE',
        icon: Icons.confirmation_number_outlined,
      ),
      _HeaderInfoRow(
        label: 'Fecha/Hora',
        value: _formatFecha(_fechaActual),
        icon: Icons.access_time,
      ),
      const SizedBox(height: 12),
      AutocompleteCreatable<Camion>(
        items: _unidos('camion', data.camiones),
        label: (v) => v.placa,
        search: (v) => '${v.placa} ${v.color ?? ''}',
        required: true,
        fieldName: 'Camión (Placa)',
        icon: Icons.directions_car,
        hint: 'Placa del camión',
        fieldKey: const Key('placa_field'),
        onFocusNodeReady: (node) => _focos[_idxCamion] = node,
        onSelected: (v) => setState(() {
          _camionSeleccionado = v;
          _confirmarCampo(_idxCamion);
        }),
        onTextChanged: (text) {
          _camionSeleccionado = null;
          _camionTexto = text.trim();
          _desconfirmarCampo(_idxCamion);
        },
        onCreated: (v) => _registrarNuevo('camion', v),
        crear: _puedePesoManual ? _specCamion : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxCamion),
      ),
      const SizedBox(height: 10),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Tiene remolque', style: TextStyle(fontSize: 13.5)),
        value: _remolque,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        onChanged: (v) => setState(() {
          _remolque = v;
          if (!v) {
            _remolqueSeleccionado = null;
            _pesoRemolqueCtrl.clear();
            _fotosRemolque = [];
            _confirmados[_idxRemolque] = false;
          }
        }),
      ),
      if (_remolque) ...[
        const SizedBox(height: 10),
        AutocompleteCreatable<Trailer>(
          items: _unidos('remolque', trailers),
          label: (t) => t.placa,
          search: (t) => '${t.placa} ${t.tipo ?? ''}',
          required: false,
          fieldName: 'Remolque',
          icon: Icons.local_shipping_outlined,
          hint: 'Placa del remolque',
          onFocusNodeReady: (node) => _focos[_idxRemolque] = node,
          onSelected: _onRemolqueSeleccionado,
          onTextChanged: (text) {
            _remolqueSeleccionado = null;
            _remolqueTexto = text.trim();
            _desconfirmarCampo(_idxRemolque);
          },
          onCreated: (t) => _registrarNuevo('remolque', t),
          crear: _puedePesoManual ? _specRemolque : null,
          onNext: () => _avanzarAlSiguienteCampo(_idxRemolque),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _pesoRemolqueCtrl,
          focusNode: _pesoRemolqueFocus,
          onChanged: (_) => _desconfirmarCampo(_idxPesoRemolque),
          onFieldSubmitted: (_) {
            _confirmarCampo(_idxPesoRemolque);
            _avanzarAlSiguienteCampo(_idxPesoRemolque);
          },
          decoration: const InputDecoration(
            labelText: 'Peso Remolque Entrada (kg)',
            hintText: 'Se sugiere la tara del remolque',
            prefixIcon: Icon(Icons.fitness_center),
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            final num = double.tryParse(v);
            if (num == null || num < 0) return 'Peso debe ser positivo';
            return null;
          },
        ),
      ],
      const SizedBox(height: 10),
      AutocompleteCreatable<Transport>(
        items: _unidos('transporte', data.transports),
        label: (t) => t.etiqueta,
        search: (t) => '${t.razonSocial} ${t.codigo ?? ''} ${t.contacto ?? ''}',
        required: false,
        fieldName: 'Transporte',
        icon: Icons.fire_truck_outlined,
        hint: 'Razón social del transporte',
        onFocusNodeReady: (node) => _focos[_idxTransporte] = node,
        onSelected: (t) => setState(() {
          _transporteSeleccionado = t;
          _confirmarCampo(_idxTransporte);
        }),
        onTextChanged: (text) {
          _transporteSeleccionado = null;
          _transporteTexto = text.trim();
          _desconfirmarCampo(_idxTransporte);
        },
        onCreated: (t) => _registrarNuevo('transporte', t),
        crear: _puedePesoManual ? _specTransporte : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxTransporte),
      ),
      const SizedBox(height: 10),
      AutocompleteCreatable<Driver>(
        items: _unidos('conductor', data.drivers),
        label: (d) => '${d.nombreCompleto} (${d.cedulaDni})',
        search: (d) => '${d.nombreCompleto} ${d.cedulaDni}',
        required: false,
        fieldName: 'Conductor',
        icon: Icons.person,
        hint: 'Cédula o nombre del conductor',
        onFocusNodeReady: (node) => _focos[_idxConductor] = node,
        onSelected: (d) => setState(() {
          _conductorSeleccionado = d;
          _confirmarCampo(_idxConductor);
        }),
        onTextChanged: (text) {
          _conductorSeleccionado = null;
          _conductorTexto = text.trim();
          _desconfirmarCampo(_idxConductor);
        },
        onCreated: (d) => _registrarNuevo('conductor', d),
        crear: _puedePesoManual
            ? CreatableSpec<Driver>(
                path: ApiConstants.conductores,
                titulo: 'Nuevo Conductor',
                icon: Icons.person,
                parse: Driver.fromJson,
                campos: [
                  CrearCampoSpec(key: 'nombre_completo', label: 'Nombre completo', icon: Icons.person_outline, requerido: true,
                      initial: _pareceCedula(_conductorTexto) ? null : _conductorTexto),
                  CrearCampoSpec(key: 'cedula_dni', label: 'Cédula / DNI', icon: Icons.badge_outlined, requerido: true,
                      initial: _pareceCedula(_conductorTexto) ? _conductorTexto : null),
                  const CrearCampoSpec(key: 'telefono', label: 'Teléfono', icon: Icons.phone_outlined),
                  const CrearCampoSpec(key: 'licencia_conducir', label: 'Licencia de conducir', icon: Icons.credit_card_outlined),
                ],
              )
            : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxConductor),
      ),
      const SizedBox(height: 10),
      AutocompleteCreatable<Product>(
        items: _unidos('producto', data.products),
        label: (p) => p.etiqueta,
        search: (p) => '${p.nombre} ${p.codigo ?? ''}',
        required: false,
        fieldName: 'Producto',
        icon: Icons.inventory,
        hint: 'Nombre del producto',
        onFocusNodeReady: (node) => _focos[_idxProducto] = node,
        onSelected: (p) => setState(() {
          _productoSeleccionado = p;
          _confirmarCampo(_idxProducto);
        }),
        onTextChanged: (text) {
          _productoSeleccionado = null;
          _productoTexto = text.trim();
          _desconfirmarCampo(_idxProducto);
        },
        onCreated: (p) => _registrarNuevo('producto', p),
        crear: _puedePesoManual ? _specProducto : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxProducto),
      ),
      const SizedBox(height: 10),
      AutocompleteCreatable<Warehouse>(
        items: _unidos('almacen', data.warehouses),
        label: (w) => w.etiqueta,
        search: (w) => '${w.nombre} ${w.codigo ?? ''}',
        required: false,
        fieldName: 'Almacén',
        icon: Icons.warehouse,
        hint: 'Nombre del almacén',
        onFocusNodeReady: (node) => _focos[_idxAlmacen] = node,
        onSelected: (w) => setState(() {
          _almacenSeleccionado = w;
          _confirmarCampo(_idxAlmacen);
        }),
        onTextChanged: (text) {
          _almacenSeleccionado = null;
          _almacenTexto = text.trim();
          _desconfirmarCampo(_idxAlmacen);
        },
        onCreated: (w) => _registrarNuevo('almacen', w),
        crear: _puedePesoManual ? _specAlmacen : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxAlmacen),
      ),
      const SizedBox(height: 10),
      AutocompleteCreatable<Scale>(
        items: _unidos('balanza', data.scales),
        label: (s) => s.etiqueta,
        search: (s) => '${s.descripcion} ${s.codigo ?? ''} ${s.marca ?? ''}',
        required: false,
        fieldName: 'Balanza',
        icon: Icons.scale,
        hint: 'Descripción de la balanza',
        onFocusNodeReady: (node) => _focos[_idxBalanza] = node,
        onSelected: (s) => setState(() {
          _balanzaSeleccionada = s;
          _confirmarCampo(_idxBalanza);
        }),
        onTextChanged: (text) {
          _balanzaSeleccionada = null;
          _balanzaTexto = text.trim();
          _desconfirmarCampo(_idxBalanza);
        },
        onCreated: (s) => _registrarNuevo('balanza', s),
        crear: _puedePesoManual ? _specBalanza : null,
        onNext: () => _avanzarAlSiguienteCampo(_idxBalanza),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              focusNode: _tipoTerceroFocus,
              initialValue: _tipoTercero,
              decoration: const InputDecoration(
                labelText: 'Tipo de Tercero',
                prefixIcon: Icon(Icons.people_outline),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'CLIENTE', child: Text('Cliente')),
                DropdownMenuItem(value: 'PROVEEDOR', child: Text('Proveedor')),
                DropdownMenuItem(value: 'AMBOS', child: Text('Ambos')),
              ],
              onChanged: (v) => setState(() {
                _tipoTercero = v ?? 'CLIENTE';
                _terceroSeleccionado = null;
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AutocompleteCreatable<ThirdParty>(
              items: _unidos('tercero', terceros),
              label: (t) => t.etiqueta,
              search: (t) => '${t.razonSocial} ${t.codigo ?? ''} ${t.identificacionFiscal ?? ''} ${t.tipo}',
              required: false,
              fieldName: 'Razón Social',
              icon: Icons.business,
              hint: 'Nombre del tercero',
              onFocusNodeReady: (node) => _focos[_idxTercero] = node,
              onSelected: (t) => setState(() {
                _terceroSeleccionado = t;
                _confirmarCampo(_idxTercero);
              }),
              onTextChanged: (text) {
                _terceroSeleccionado = null;
                _terceroTexto = text.trim();
                _desconfirmarCampo(_idxTercero);
              },
              onCreated: (t) => _registrarNuevo('tercero', t),
              crear: _puedePesoManual
                  ? CreatableSpec<ThirdParty>(
                      path: ApiConstants.terceros,
                      titulo: 'Nuevo Tercero',
                      icon: Icons.business,
                      parse: ThirdParty.fromJson,
                      campos: [
                        const CrearCampoSpec(key: 'razon_social', label: 'Razón social', icon: Icons.badge_outlined, requerido: true, precargarTexto: true),
                        CrearCampoSpec(key: 'tipo', label: 'Tipo', icon: Icons.category_outlined, tipo: CrearCampoTipo.dropdown, opciones: ['CLIENTE', 'PROVEEDOR', 'AMBOS'], requerido: true, initial: _tipoTercero),
                        const CrearCampoSpec(key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
                        const CrearCampoSpec(key: 'identificacion_fiscal', label: 'RIF / Identificación fiscal', icon: Icons.badge_outlined),
                        const CrearCampoSpec(key: 'telefono', label: 'Teléfono', icon: Icons.phone_outlined),
                        const CrearCampoSpec(key: 'direccion', label: 'Dirección', icon: Icons.place_outlined, tipo: CrearCampoTipo.multilinea),
                        const CrearCampoSpec(key: 'email', label: 'Email', icon: Icons.email_outlined, tipo: CrearCampoTipo.email),
                      ],
                    )
                  : null,
              onNext: () => _avanzarAlSiguienteCampo(_idxTercero),
            ),
          ),
        ],
      ),
    ];
  }

  /// Lectura de pesos:
  /// - Si HAY báscula registrada → `ScaleMonitorWidget` (peso en vivo).
  /// - Si NO hay báscula → aviso sobrio "Peso manual" + campo editable.
  List<Widget> _buildLecturaSection(BuildContext context) {
    return [
      if (_hayBascula)
        ScaleMonitorWidget(
          client: _scaleClient,
          label: _balanzaSeleccionada?.descripcion ?? 'Báscula',
          balanzaId: _balanzaSeleccionada?.id,
          balanzaDescripcion: _balanzaSeleccionada?.descripcion,
          initialWeight: double.tryParse(_pesoEntradaCtrl.text) ?? 0,
          onPesoLeido: (peso) {
            setState(() {
              _pesoEntradaCtrl.text = peso.toStringAsFixed(2);
            });
          },
        )
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: SwsColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: SwsColors.warning.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: SwsColors.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Peso manual — no hay báscula conectada',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('peso_entrada_field'),
        controller: _pesoEntradaCtrl,
        focusNode: _pesoEntradaFocus,
        readOnly: !_esPesoManual,
        onChanged: (_) => _desconfirmarCampo(_idxPesoEntrada),
        onFieldSubmitted: (_) {
          _confirmarCampo(_idxPesoEntrada);
          _avanzarAlSiguienteCampo(_idxPesoEntrada);
        },
        decoration: InputDecoration(
          labelText: 'Peso Entrada Vehículo (kg) *',
          prefixIcon: !_esPesoManual
              ? const Icon(Icons.link)
              : const Icon(Icons.monitor_weight),
          helperText: _esPesoManual
              ? 'Registro manual (solo Supervisor/Admin)'
              : 'Peso registrado por la báscula: no se puede editar',
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => Validators.positiveNumber(v, 'Peso'),
      ),
      if (_puedePesoManual && _hayBascula) ...[
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Registro manual del peso',
              style: TextStyle(fontSize: 12.5)),
          subtitle: const Text('Solo Supervisor/Admin',
              style: TextStyle(fontSize: 11)),
          value: _esPesoManual,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _esPesoManual = v),
        ),
      ],
      const SizedBox(height: 8),
      _WeightTable(
        pesoEntrada: double.tryParse(_pesoEntradaCtrl.text) ?? 0,
        pesoRemolqueEntrada: double.tryParse(_pesoRemolqueCtrl.text),
        pesoSalida: null,
        pesoRemolqueSalida: null,
        pesoNetoDeclarado: double.tryParse(_pesoNetoDeclaradoCtrl.text),
      ),
    ];
  }

  List<Widget> _buildAdicionalesSection(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _documentoCtrl,
              focusNode: _documentoFocus,
              onChanged: (_) => _desconfirmarCampo(_idxDocumento),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxDocumento);
                _avanzarAlSiguienteCampo(_idxDocumento);
              },
              decoration: const InputDecoration(
                labelText: 'Documento',
                prefixIcon: Icon(Icons.description),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _guiaSunagroCtrl,
              focusNode: _guiaSunagroFocus,
              onChanged: (_) => _desconfirmarCampo(_idxGuiaSunagro),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxGuiaSunagro);
                _avanzarAlSiguienteCampo(_idxGuiaSunagro);
              },
              decoration: const InputDecoration(
                labelText: 'Guía SUNAGRO',
                prefixIcon: Icon(Icons.receipt_long),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _medidaCtrl,
              focusNode: _medidaFocus,
              onChanged: (_) => _desconfirmarCampo(_idxMedida),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxMedida);
                _avanzarAlSiguienteCampo(_idxMedida);
              },
              decoration: const InputDecoration(
                labelText: 'Medida',
                hintText: 'Litros, Galones...',
                prefixIcon: Icon(Icons.straighten_outlined),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _unidadesCtrl,
              focusNode: _unidadesFocus,
              onChanged: (_) => _desconfirmarCampo(_idxUnidades),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxUnidades);
                _avanzarAlSiguienteCampo(_idxUnidades);
              },
              decoration: const InputDecoration(
                labelText: 'Unidades',
                prefixIcon: Icon(Icons.inventory_2_outlined),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _densidadCtrl,
              focusNode: _densidadFocus,
              onChanged: (_) => _desconfirmarCampo(_idxDensidad),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxDensidad);
                _avanzarAlSiguienteCampo(_idxDensidad);
              },
              decoration: const InputDecoration(
                labelText: 'Densidad',
                prefixIcon: Icon(Icons.speed_outlined),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _fleteCtrl,
              focusNode: _fleteFocus,
              onChanged: (_) => _desconfirmarCampo(_idxFlete),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxFlete);
                _avanzarAlSiguienteCampo(_idxFlete);
              },
              decoration: const InputDecoration(
                labelText: 'Flete (ref.)',
                prefixIcon: Icon(Icons.local_shipping_outlined),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _costoFleteCtrl,
              focusNode: _costoFleteFocus,
              onChanged: (_) => _desconfirmarCampo(_idxCostoFlete),
              onFieldSubmitted: (_) {
                _confirmarCampo(_idxCostoFlete);
                _avanzarAlSiguienteCampo(_idxCostoFlete);
              },
              decoration: const InputDecoration(
                labelText: 'Costo del Flete',
                prefixIcon: Icon(Icons.attach_money),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final num = double.tryParse(v);
                if (num == null || num < 0) return 'Costo debe ser positivo';
                return null;
              },
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildObservacionesSection() {
    return [
      TextFormField(
        controller: _observacionesCtrl,
        focusNode: _observacionesFocus,
        onChanged: (_) => _desconfirmarCampo(_idxObservaciones),
        onFieldSubmitted: (_) {
          _confirmarCampo(_idxObservaciones);
          _avanzarAlSiguienteCampo(_idxObservaciones);
        },
        decoration: const InputDecoration(
          hintText: 'Observaciones del pesaje...',
          border: OutlineInputBorder(),
        ),
        maxLines: 4,
        maxLength: 500,
        buildCounter: (context, {required currentLength, required isFocused, required maxLength}) => null,
      ),
    ];
  }

  List<Widget> _buildResumenSection(CatalogData data) {
    final pts = double.tryParse(_pesoRemolqueCtrl.text);
    return [
      _ResumenRow(label: 'Serie - Boleto', value: _numeroBoleto ?? 'PENDIENTE'),
      _ResumenRow(label: 'Camión', value: _camionSeleccionado?.placa ?? _camionTexto.toUpperCase()),
      _ResumenRow(label: 'Remolque', value: _remolque ? (_remolqueSeleccionado?.placa ?? 'Sí') : 'No'),
      _ResumenRow(label: 'Transporte', value: _transporteSeleccionado?.razonSocial ?? _transporteTexto),
      _ResumenRow(label: 'Conductor', value: _conductorSeleccionado?.nombreCompleto ?? _conductorTexto),
      _ResumenRow(label: 'Producto', value: _productoSeleccionado?.nombre ?? _productoTexto),
      _ResumenRow(label: 'Almacén', value: _almacenSeleccionado?.nombre ?? _almacenTexto),
      _ResumenRow(label: 'Selección', value: _tipoTercero),
      _ResumenRow(label: 'Razón Social', value: _terceroSeleccionado?.razonSocial ?? _terceroTexto),
      const Divider(height: 20),
      _ResumenRow(label: 'Peso Camión', value: NumberUtils.formatKg(double.tryParse(_pesoEntradaCtrl.text)), highlight: true),
      if (pts != null && _remolque) _ResumenRow(label: 'Peso Remolque', value: NumberUtils.formatKg(pts)),
      _ResumenRow(label: 'Peso Total Entrada', value: NumberUtils.formatKg(_pesoTotalEntrada), highlight: true),
      _ResumenRow(label: 'Peso Neto Declarado', value: NumberUtils.formatKg(_pesoNetoDeclarado)),
      _ResumenRow(label: 'Diferencia', value: NumberUtils.formatKg(_pesoDiferencia), highlight: _pesoDiferencia != 0),
      _ResumenRow(label: '% Desviación', value: NumberUtils.formatPercent(_porcentajeDesviacion)),
    ];
  }

  List<Widget> _buildFotosSection() {
    return [
      PhotoPickerField(
        label: 'Fotos del camión',
        icon: Icons.directions_car_outlined,
        fotos: _fotosCamion,
        onChanged: (f) => setState(() => _fotosCamion = f),
      ),
      if (_remolque) ...[
        const SizedBox(height: 8),
        PhotoPickerField(
          label: 'Fotos del remolque',
          icon: Icons.local_shipping_outlined,
          fotos: _fotosRemolque,
          onChanged: (f) => setState(() => _fotosRemolque = f),
        ),
      ],
    ];
  }

  String _formatFecha(DateTime? fecha) {
    if (fecha == null) return '';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }
}

class _QuickActionBar extends StatelessWidget {
  final VoidCallback onEntrada;
  final VoidCallback onGuardar;
  final VoidCallback onCancelar;
  final VoidCallback onImprimir;
  final VoidCallback onSalir;
  final bool puedeAnular;

  const _QuickActionBar({
    required this.onEntrada,
    required this.onGuardar,
    required this.onCancelar,
    required this.onImprimir,
    required this.onSalir,
    required this.puedeAnular,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SwsColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _ToolbarButton(icon: Icons.input, label: 'Entrada', shortcut: 'F2', onTap: onEntrada, color: SwsColors.success),
          const SizedBox(width: 6),
          _ToolbarButton(icon: Icons.save, label: 'Guardar', shortcut: 'F4', onTap: onGuardar, color: SwsColors.accent),
          const SizedBox(width: 6),
          _ToolbarButton(icon: Icons.cancel_outlined, label: 'Cancelar', shortcut: 'Esc', onTap: onCancelar),
          const SizedBox(width: 6),
          _ToolbarButton(icon: Icons.print, label: 'Imprimir', shortcut: 'F5', onTap: onImprimir),
          const SizedBox(width: 6),
          _ToolbarButton(icon: Icons.exit_to_app, label: 'Salir', onTap: onSalir),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.shortcut,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? Colors.white70;
    return Tooltip(
      message: shortcut != null ? '$label ($shortcut)' : label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color?.withValues(alpha: 0.15) ?? Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: btnColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: btnColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(shortcut!, style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: SwsColors.accent),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SwsColors.primary)),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HeaderInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _HeaderInfoRow({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: SwsColors.gray400),
            const SizedBox(width: 6),
          ],
          Text('$label: ', style: const TextStyle(fontSize: 12.5, color: SwsColors.gray500, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ResumenRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _ResumenRow({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                color: highlight
                    ? SwsColors.accent
                    : (oscuro ? SwsColors.darkText : SwsColors.dark),
              ),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightTable extends StatelessWidget {
  final double pesoEntrada;
  final double? pesoRemolqueEntrada;
  final double? pesoSalida;
  final double? pesoRemolqueSalida;
  final double? pesoNetoDeclarado;

  const _WeightTable({
    required this.pesoEntrada,
    this.pesoRemolqueEntrada,
    this.pesoSalida,
    this.pesoRemolqueSalida,
    this.pesoNetoDeclarado,
  });

  @override
  Widget build(BuildContext context) {
    final pte = pesoEntrada + (pesoRemolqueEntrada ?? 0);
    final pts = pesoSalida != null ? pesoSalida! + (pesoRemolqueSalida ?? 0) : null;
    final pnt = pts != null ? pte - pts : null;
    final pnd = pesoNetoDeclarado ?? 0;
    final pdf = pnt != null ? pnt - pnd : null;
    final pdv = (pdf != null && pnd != 0) ? (pdf / pnd) * 100 : null;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: oscuro ? SwsColors.darkCard : SwsColors.blue100,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _weightRow(context, 'Balanza Entrada', NumberUtils.formatKg(pesoEntrada), NumberUtils.formatKg(pesoRemolqueEntrada), NumberUtils.formatKg(pte)),
            if (pesoSalida != null) ...[
              _weightRow(context, 'Balanza Salida', NumberUtils.formatKg(pesoSalida), NumberUtils.formatKg(pesoRemolqueSalida), NumberUtils.formatKg(pts)),
              const Divider(height: 16),
              _weightRow(context, 'Peso Neto', '', '', NumberUtils.formatKg(pnt), bold: true),
              _weightRow(context, 'Peso Declarado', '', '', NumberUtils.formatKg(pnd)),
              _weightRow(context, 'Diferencia', '', '', NumberUtils.formatKg(pdf), bold: pdf != null && pdf != 0),
              _weightRow(context, '% Desviación', '', '', NumberUtils.formatPercent(pdv)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _weightRow(BuildContext context, String label, String camion, String remolque, String total, {bool bold = false}) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final texto = oscuro ? SwsColors.darkText : SwsColors.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          ),
          if (camion.isNotEmpty)
            Expanded(flex: 2, child: Text(camion, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
          if (remolque.isNotEmpty)
            Expanded(flex: 2, child: Text(remolque, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
          Expanded(
            flex: 2,
            child: Text(total, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: bold ? SwsColors.accent : texto,
            )),
          ),
        ],
      ),
    );
  }
}