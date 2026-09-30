import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart' as app_dates;
import '../../../core/utils/medida_conversion.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/unsaved_work_guard.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/forms/autocomplete_creatable.dart';
import '../../../core/widgets/forms/create_item_dialog.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/repositories/weighing_repository.dart'
    show WeighingRepository;
import '../../../data/services/scale_api_client.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/entities/weighing.dart';
import '../../widgets/ticket_preview_dialog.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/catalog/catalog_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';

const _specCamion = CreatableSpec<Camion>(
  path: ApiConstants.camiones,
  titulo: 'Nuevo Camión',
  icon: Icons.directions_car,
  parse: Camion.fromJson,
  campos: [
    CrearCampoSpec(
        key: 'placa',
        label: 'Placa',
        icon: Icons.tag_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(key: 'color', label: 'Color', icon: Icons.palette_outlined),
    CrearCampoSpec(
        key: 'tara_habitual',
        label: 'Tara habitual (kg)',
        icon: Icons.fitness_center,
        tipo: CrearCampoTipo.numero),
  ],
);

const _specRemolque = CreatableSpec<Trailer>(
  path: ApiConstants.remolques,
  titulo: 'Nuevo Remolque',
  icon: Icons.local_shipping_outlined,
  parse: Trailer.fromJson,
  campos: [
    CrearCampoSpec(
        key: 'placa',
        label: 'Placa',
        icon: Icons.tag_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(
        key: 'tipo_remolque',
        label: 'Tipo de remolque',
        icon: Icons.category_outlined),
    CrearCampoSpec(
        key: 'tara_habitual',
        label: 'Tara habitual (kg)',
        icon: Icons.fitness_center,
        tipo: CrearCampoTipo.numero),
  ],
);

const _specTransporte = CreatableSpec<Transport>(
  path: ApiConstants.transportes,
  titulo: 'Nuevo Transporte',
  icon: Icons.fire_truck_outlined,
  parse: Transport.fromJson,
  campos: [
    CrearCampoSpec(
        key: 'razon_social',
        label: 'Razón social',
        icon: Icons.badge_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(
        key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(
        key: 'identificacion_fiscal',
        label: 'RIF / Identificación fiscal',
        icon: Icons.badge_outlined),
    CrearCampoSpec(
        key: 'contacto', label: 'Contacto', icon: Icons.person_outline),
    CrearCampoSpec(
        key: 'telefono', label: 'Teléfono', icon: Icons.phone_outlined),
  ],
);

const _specProducto = CreatableSpec<Product>(
  path: ApiConstants.productos,
  titulo: 'Nuevo Producto',
  icon: Icons.inventory,
  parse: Product.fromJson,
  campos: [
    CrearCampoSpec(
      key: 'id_categoria',
      label: 'Categoría',
      icon: Icons.category_outlined,
      tipo: CrearCampoTipo.dropdown,
      requerido: true,
      catalogoPath: ApiConstants.categorias,
      catalogoIdKey: 'id_categoria',
      catalogoTituloKey: 'nombre',
    ),
    CrearCampoSpec(
        key: 'nombre',
        label: 'Nombre',
        icon: Icons.badge_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(
        key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(
        key: 'densidad_estandar',
        label: 'Densidad estándar (kg/L)',
        icon: Icons.speed_outlined,
        tipo: CrearCampoTipo.numero),
    CrearCampoSpec(
      key: 'unidad_medida',
      label: 'Unidad de medida',
      icon: Icons.straighten_outlined,
      tipo: CrearCampoTipo.dropdown,
      opciones: ['KG', 'TON', 'L', 'GAL', 'UN'],
    ),
    CrearCampoSpec(
        key: 'peso_unidad',
        label: 'Peso por unidad (kg)',
        icon: Icons.inventory_2_outlined,
        tipo: CrearCampoTipo.numero),
    CrearCampoSpec(
        key: 'es_kardex',
        label: 'Generar movimiento de kardex',
        icon: Icons.book_outlined,
        tipo: CrearCampoTipo.booleano),
  ],
);

const _specAlmacen = CreatableSpec<Warehouse>(
  path: ApiConstants.almacenes,
  titulo: 'Nuevo Almacén',
  icon: Icons.warehouse,
  parse: Warehouse.fromJson,
  campos: [
    CrearCampoSpec(
        key: 'nombre',
        label: 'Nombre',
        icon: Icons.badge_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(
        key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(
        key: 'ubicacion', label: 'Ubicación', icon: Icons.place_outlined),
  ],
);

const _specBalanza = CreatableSpec<Scale>(
  path: ApiConstants.balanzas,
  titulo: 'Nueva Balanza',
  icon: Icons.scale,
  parse: Scale.fromJson,
  campos: [
    CrearCampoSpec(
        key: 'descripcion',
        label: 'Descripción',
        icon: Icons.badge_outlined,
        requerido: true,
        precargarTexto: true),
    CrearCampoSpec(
        key: 'codigo', label: 'Código', icon: Icons.numbers_outlined),
    CrearCampoSpec(
        key: 'marca', label: 'Marca', icon: Icons.local_offer_outlined),
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

class _WeighingFormAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      title: Text(context.tr('Estación de Pesaje'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}

/// Paso de la captura guiada cabina → remolque.
enum _ObjetivoPeso { cabina, remolque, fijado }

/// Escribe el estado en el registro global que consulta el cierre de ventana.
void _marcarDatosSinGuardarGlobal(bool hayDatos) {
  tieneDatosSinGuardar = hayDatos;
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
  static const int _idxCamion = 0;
  static const int _idxRemolque = 1;
  static const int _idxTransporte = 2;
  static const int _idxConductor = 3;
  static const int _idxProducto = 4;
  static const int _idxAlmacen = 5;
  static const int _idxBalanza = 6;
  static const int _idxTipoTercero = 7;
  static const int _idxTercero = 8;
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
  final _unidadesCtrl = TextEditingController();
  final _densidadCtrl = TextEditingController();
  final _pesoUnidadCtrl = TextEditingController();
  final _fleteCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  final _pesoSalidaVehiculoCtrl = TextEditingController();
  final _pesoSalidaRemolqueCtrl = TextEditingController();
  final _pesoSalidaVehiculoFocus = FocusNode();
  final _pesoSalidaRemolqueFocus = FocusNode();
  Weighing? _boletoSalida;

  bool _remolque = false;
  String _tipoTercero = 'CLIENTE';
  bool _esPesoManual = false;
  bool _puedePesoManual = false;
  bool _hayBascula = false;

  /// Medida de facturación elegida (la báscula siempre entrega kg).
  UnidadMedida? _medida;

  /// `DropdownButtonFormField` solo toma `initialValue` al crearse: esta
  /// semilla fuerza el refresco cuando la medida cambia por código (cargar
  /// boleto, autocompletar desde el producto, limpiar el formulario).
  int _medidaSeed = 0;

  /// Asigna la medida; [refrescarCampo] debe ser `false` cuando el cambio
  /// viene del propio desplegable (su estado ya está actualizado).
  void _asignarMedida(UnidadMedida? medida, {bool refrescarCampo = true}) {
    _medida = medida;
    if (refrescarCampo) _medidaSeed++;
  }

  /// `true` cuando el operador escribió `Unidades` a mano: en ese caso el
  /// autocalculado deja de sobrescribir el campo.
  bool _unidadesEditadas = false;

  /// Peso por unidad (kg/saco) tomado del producto seleccionado.
  double? _pesoUnidadProducto;

  /// Tolerancia comercial (%) tomada del producto (MODEL.md).
  double? _toleranciaProducto;

  /// True cuando el formulario tiene captura que se perdería al cerrar.
  ///
  /// Lo consultan el `Esc` del formulario y el cierre de ventana (main.dart).
  bool _tieneDatosSinGuardar = false;

  /// Paso de la captura guiada cabina → remolque. La báscula vuelca su
  /// lectura en el campo del paso activo; al pasar al remolque la cabina
  /// queda congelada (con una sola báscula no se puede leer las dos a la vez).
  _ObjetivoPeso _objetivoPeso = _ObjetivoPeso.cabina;

  /// `true` cuando falta pesar el remolque (aviso de avance activo).
  bool get _guiaRemolque => _objetivoPeso == _ObjetivoPeso.remolque;

  /// Campo que recibe la lectura en vivo de la báscula (null = ambos fijados).
  TextEditingController? get _ctrlActivoPeso => switch (_objetivoPeso) {
        _ObjetivoPeso.cabina =>
          _boletoSalida != null ? _pesoSalidaVehiculoCtrl : _pesoEntradaCtrl,
        _ObjetivoPeso.remolque =>
          _boletoSalida != null ? _pesoSalidaRemolqueCtrl : _pesoRemolqueCtrl,
        _ObjetivoPeso.fijado => null,
      };

  /// Catálogo de básculas cargado para resolver la báscula por defecto.
  List<Scale> _balanzasDisponibles = const [];

  /// `true` mientras hay una alerta de flujo abierta: bloquea atajos y guardado.
  bool _alertaAbierta = false;

  /// Pesaje original del que se copiaron los datos (búsqueda rápida). Nunca se
  /// modifica: al guardar se crea un pesaje nuevo con la fecha de hoy.
  Weighing? _origenCopia;

  /// Catálogo cacheado para resolver las entidades del pesaje copiado.
  CatalogData _catalogos = CatalogData.empty;

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
  String? _ultimoBoletoId;
  String? _ultimoNumeroBoleto;
  DateTime? _fechaActual;

  List<dynamic> _series = [];
  String? _idSerieSeleccionada;
  Map<String, dynamic>? _serieActiva;
  bool _guardandoPesaje = false;

  @override
  void initState() {
    super.initState();
    _fechaActual = DateTime.now();
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
    _cargarSeries();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
    for (final c in _controlesConDatos) {
      c.addListener(_actualizarDatosSinGuardar);
    }
    _marcarDatosSinGuardarGlobal(false);
  }

  /// Controles cuyo contenido cuenta como captura sin guardar.
  List<TextEditingController> get _controlesConDatos => [
        _pesoEntradaCtrl,
        _pesoRemolqueCtrl,
        _pesoSalidaVehiculoCtrl,
        _pesoSalidaRemolqueCtrl,
        _pesoNetoDeclaradoCtrl,
        _documentoCtrl,
        _guiaSunagroCtrl,
        _unidadesCtrl,
        _densidadCtrl,
        _fleteCtrl,
        _costoFleteCtrl,
        _observacionesCtrl,
      ];

  Future<void> _cargarSeries() async {
    try {
      final resp = await di.sl<ApiClient>().listSeries();
      final listado = resp.data is List ? (resp.data as List) : [];
      if (mounted) {
        setState(() {
          _series = listado;
          final activa = listado.firstWhere(
            (s) => s['activa'] == true,
            orElse: () => listado.isNotEmpty ? listado.first : null,
          );
          if (activa != null) {
            _serieActiva = Map<String, dynamic>.from(activa);
            _idSerieSeleccionada = activa['id_serie']?.toString();
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    for (final c in _controlesConDatos) {
      c.removeListener(_actualizarDatosSinGuardar);
    }
    tieneDatosSinGuardar = false;
    _scrollController.dispose();
    _tipoTerceroFocus.dispose();
    _pesoEntradaFocus.dispose();
    _pesoRemolqueFocus.dispose();
    _pesoSalidaVehiculoFocus.dispose();
    _pesoSalidaRemolqueFocus.dispose();
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
    _pesoSalidaVehiculoCtrl.dispose();
    _pesoSalidaRemolqueCtrl.dispose();
    _pesoNetoDeclaradoCtrl.dispose();
    _documentoCtrl.dispose();
    _guiaSunagroCtrl.dispose();
    _pesoUnidadCtrl.dispose();
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
    List<Scale> balanzas = const [];
    try {
      final api = di.sl<ApiClient>();
      final res = await api.getList(ApiConstants.balanzas);
      final data = res.data;
      hayBascula = data is List && data.isNotEmpty;
      if (data is List) {
        balanzas =
            data.whereType<Map<String, dynamic>>().map(Scale.fromJson).toList();
      }
    } catch (_) {
      hayBascula = false;
    }
    if (!mounted) return;
    setState(() {
      _puedePesoManual = user?.rol == 'ADMIN' || user?.rol == 'SUPERVISOR';
      _hayBascula = hayBascula;
      _esPesoManual = !hayBascula;
      _balanzasDisponibles = balanzas;
      _aplicarBalanzaPorDefecto(modoSalida: _boletoSalida != null);
    });
  }

  /// Keys de preferencias para la báscula por defecto según el tipo de pesaje.
  static const String _prefsBalanzaGlobal = 'scale_default_id';
  static const String _prefsBalanzaEntrada = 'scale_default_entrada_id';
  static const String _prefsBalanzaSalida = 'scale_default_salida_id';

  /// Preselecciona la báscula configurada para entradas o salidas, con
  /// reserva a la báscula global del sistema. No pisa la elección manual.
  void _aplicarBalanzaPorDefecto({required bool modoSalida}) {
    if (_balanzaSeleccionada != null) return;
    // Con una sola báscula registrada esa es la default de entradas y salidas.
    if (_balanzasDisponibles.length == 1) {
      _balanzaSeleccionada = _balanzasDisponibles.first;
      _balanzaTexto = _balanzaSeleccionada!.etiqueta;
      _confirmados[_idxBalanza] = true;
      return;
    }
    final prefs = AppConfig.prefs;
    final idPreferido = (modoSalida
            ? prefs.getString(_prefsBalanzaSalida)
            : prefs.getString(_prefsBalanzaEntrada)) ??
        prefs.getString(_prefsBalanzaGlobal);
    if (idPreferido == null || idPreferido.isEmpty) return;
    final coincidencias =
        _balanzasDisponibles.where((b) => b.id == idPreferido);
    if (coincidencias.isEmpty) return;
    _balanzaSeleccionada = coincidencias.first;
    _balanzaTexto = _balanzaSeleccionada!.etiqueta;
    _confirmados[_idxBalanza] = true;
  }

  // ─── Atajos de teclado ────────────────────────────────────────────────
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (_alertaAbierta) return false;

    if (key == LogicalKeyboardKey.f2) {
      _registrarEntrada();
      return true;
    }
    if (key == LogicalKeyboardKey.f3) {
      _capturarPeso();
      return true;
    }
    if (key == LogicalKeyboardKey.f4) {
      _onSave();
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      _abrirSelectorImpresion();
      return true;
    }
    if (key == LogicalKeyboardKey.f6) {
      _abrirSelectorSalida();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Si hay un diálogo/popup abierto, dejarlo cerrarse a él.
      if (_hayDialogAbierto()) return false;
      _salirConConfirmacion();
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

  /// Cierra el formulario; si hay captura sin guardar pide confirmación.
  Future<void> _salirConConfirmacion() async {
    if (!_tieneDatosSinGuardar) {
      Navigator.of(context).pop();
      return;
    }
    final salir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: SwsColors.danger, size: 36),
        title: Text('weighing_unsaved_cancel_title'.tr(),
            textAlign: TextAlign.center),
        content: Text(
          'weighing_unsaved_cancel_msg'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text('weighing_unsaved_keep_editing'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.danger),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text('weighing_unsaved_confirm_cancel'.tr()),
          ),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop();
  }

  void _confirmarCampo(int idx) {
    _confirmados[idx] = true;
    _actualizarDatosSinGuardar();
  }

  void _desconfirmarCampo(int idx) {
    _confirmados[idx] = false;
    _actualizarDatosSinGuardar();
  }

  /// Marca/desmarca la captura en curso y avisa al cierre de ventana.
  ///
  /// Hay datos sin guardar si el formulario tiene texto capturado o una
  /// lectura de báscula ya fijada (peso pendiente de boleto).
  void _actualizarDatosSinGuardar() {
    final hayTexto = [
          _documentoCtrl,
          _guiaSunagroCtrl,
          _observacionesCtrl,
          _pesoNetoDeclaradoCtrl,
          _unidadesCtrl,
          _densidadCtrl,
          _fleteCtrl,
        ].any((c) => c.text.trim().isNotEmpty) ||
        [
          _camionTexto,
          _remolqueTexto,
          _transporteTexto,
          _conductorTexto,
          _productoTexto,
          _almacenTexto,
          _terceroTexto,
        ].any((t) => t.trim().isNotEmpty);
    final hayPesos = _pesoEntradaCtrl.text.trim().isNotEmpty ||
        _pesoRemolqueCtrl.text.trim().isNotEmpty ||
        _pesoSalidaVehiculoCtrl.text.trim().isNotEmpty ||
        _pesoSalidaRemolqueCtrl.text.trim().isNotEmpty;
    final valor =
        hayTexto || hayPesos || _boletoSalida != null || _origenCopia != null;
    if (valor == _tieneDatosSinGuardar) return;
    _tieneDatosSinGuardar = valor;
    _marcarDatosSinGuardarGlobal(valor);
  }

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

  // ─── Captura guiada cabina → remolque ─────────────────────────────────
  void _avisoSimple(String mensaje, [Color? color]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color ?? SwsColors.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Peso de la cabina (vehículo) en el modo activo.
  double get _pesoCabinaActual =>
      double.tryParse(_boletoSalida != null
          ? _pesoSalidaVehiculoCtrl.text
          : _pesoEntradaCtrl.text) ??
      0;

  /// Peso del remolque en el modo activo.
  double get _pesoRemolqueActual =>
      double.tryParse(_boletoSalida != null
          ? _pesoSalidaRemolqueCtrl.text
          : _pesoRemolqueCtrl.text) ??
      0;

  /// F3 / botón *Capturar peso*: fija la lectura en curso como peso del paso
  /// activo (cabina o remolque).
  ///
  /// Con remolque: la 1.ª pulsación confirma la cabina y muestra la alerta para
  /// mover el camión; al continuar, la báscula y el indicador pasan a capturar
  /// el peso del remolque. La 2.ª pulsación lo confirma y deja los campos
  /// listos para completar los demás datos.
  Future<void> _capturarPeso() async {
    if (_alertaAbierta || _guardandoPesaje) return;
    final modoSalida = _boletoSalida != null;

    // Sin remolque la captura es un solo paso: fija y libera la lectura.
    if (!_remolque) {
      if (_pesoCabinaActual <= 0) {
        _avisoSimple('weighing_capture_cabina_first'.tr(), SwsColors.warning);
        return;
      }
      setState(() => _objetivoPeso = _objetivoPeso == _ObjetivoPeso.fijado
          ? _ObjetivoPeso.cabina
          : _ObjetivoPeso.fijado);
      _avisoSimple('weighing_weight_fixed'.tr(), SwsColors.success);
      return;
    }

    switch (_objetivoPeso) {
      case _ObjetivoPeso.cabina:
        if (_pesoCabinaActual <= 0) {
          _avisoSimple('weighing_capture_cabina_first'.tr(), SwsColors.warning);
          return;
        }
        final continuar = await _alertaMoverCamion(_pesoCabinaActual);
        if (!continuar || !mounted) return;
        // La tara sugerida del remolque no cuenta como captura.
        final ctrlRemolque =
            modoSalida ? _pesoSalidaRemolqueCtrl : _pesoRemolqueCtrl;
        final tara = _remolqueSeleccionado?.taraHabitual;
        final valor = double.tryParse(ctrlRemolque.text) ?? 0;
        if (valor <= 0 || (tara != null && (valor - tara).abs() < 0.005)) {
          ctrlRemolque.clear();
        }
        setState(() => _objetivoPeso = _ObjetivoPeso.remolque);
        (modoSalida ? _pesoSalidaRemolqueFocus : _pesoRemolqueFocus)
            .requestFocus();
      case _ObjetivoPeso.remolque:
        if (_pesoRemolqueActual <= 0) {
          _avisoSimple('weighing_trailer_waiting'.tr(), SwsColors.warning);
          return;
        }
        setState(() => _objetivoPeso = _ObjetivoPeso.fijado);
        _avisoSimple('weighing_trailer_ready'.tr(), SwsColors.success);
      case _ObjetivoPeso.fijado:
        // Volver a capturar el remolque si el camión se movió.
        setState(() => _objetivoPeso = _ObjetivoPeso.remolque);
        (modoSalida ? _pesoSalidaRemolqueFocus : _pesoRemolqueFocus)
            .requestFocus();
    }
  }

  /// Alerta tras capturar la cabina: indica al operador mover el camión.
  Future<bool> _alertaMoverCamion(double pesoCabina) async {
    _alertaAbierta = true;
    final continuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.directions_car_filled_outlined,
            color: SwsColors.accent, size: 36),
        title:
            Text('weighing_move_truck_title'.tr(), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'weighing_cabina_registered'.tr()}: '
              '${_formatoNumero(pesoCabina)} kg',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text('weighing_move_truck_msg'.tr(),
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('weighing_no_edit'.tr()),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.directions_car, size: 18),
            label: Text('weighing_continue'.tr()),
          ),
        ],
      ),
    );
    _alertaAbierta = false;
    return continuar ?? false;
  }

  /// Confirmación final antes de enviar el pesaje a la API.
  Future<bool> _confirmarGuardado() async {
    final modo =
        _boletoSalida != null ? 'weighing_mode_exit' : 'weighing_mode_entry';
    final resumen = _resumenCaptura();
    _alertaAbierta = true;
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.save_outlined, color: SwsColors.success, size: 36),
        title: Text('weighing_confirm_save_title'.tr(),
            textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTranslations.tr('weighing_confirm_save_mode',
                  args: [modo.tr()]),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(resumen, style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 8),
            Text(
              'weighing_confirm_save_hint'.tr(),
              style: const TextStyle(fontSize: 12, color: SwsColors.gray600),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('weighing_no_edit'.tr()),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.success),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check, size: 18),
            label: Text('weighing_yes_save'.tr()),
          ),
        ],
      ),
    );
    _alertaAbierta = false;
    return confirmar ?? false;
  }

  /// Última confirmación tras guardar: ¿imprimir o seguir con un nuevo peso?
  Future<void> _alertaImprimir(String numero) async {
    _alertaAbierta = true;
    final imprimir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.print_outlined, color: SwsColors.accent, size: 36),
        title:
            Text('weighing_print_question'.tr(), textAlign: TextAlign.center),
        content: Text(
          AppTranslations.tr('weighing_print_msg', args: [numero]),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.35),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.add, size: 18),
            label: Text('weighing_new_weight'.tr()),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.print, size: 18),
            label: Text('weighing_print_yes'.tr()),
          ),
        ],
      ),
    );
    _alertaAbierta = false;
    if (imprimir == true) _imprimirActual();
  }

  /// Resumen de los pesos capturados que se muestra al confirmar el guardado.
  String _resumenCaptura() {
    final modoSalida = _boletoSalida != null;
    final cabina = _pesoCabinaActual;
    final partes = <String>[
      '${'weighing_peso_cabina'.tr()}: ${_formatoNumero(cabina)} kg',
    ];
    if (_remolque) {
      partes.add(
          '${'weighing_peso_remolque'.tr()}: ${_formatoNumero(_pesoRemolqueActual)} kg');
    }
    if (modoSalida) {
      partes.add(
          '${'weighing_peso_neto'.tr()}: ${_formatoNumero(_pesoTotalEntrada - cabina - (_remolque ? _pesoRemolqueActual : 0))} kg');
    }
    return partes.join('   ·   ');
  }

  /// Texto del botón *Capturar peso* según el paso activo.
  String get _etiquetaCapturarPeso => switch (_objetivoPeso) {
        _ObjetivoPeso.cabina => _remolque
            ? 'weighing_capture_weight_cab'.tr()
            : 'weighing_capture_weight'.tr(),
        _ObjetivoPeso.remolque => 'weighing_capture_weight_rem'.tr(),
        _ObjetivoPeso.fijado => 'weighing_capture_weight_redo'.tr(),
      };

  /// Vuelve al primer paso (cabina) al limpiar o cambiar de boleto.
  void _reiniciarCapturaGuiada() {
    _objetivoPeso = _ObjetivoPeso.cabina;
  }

  /// Bloquea el guardado si con remolque falta el segundo peso.
  bool _validarPesoRemolqueObligatorio() {
    if (!_remolque) return true;
    if (_pesoRemolqueActual > 0) return true;
    _avisoSimple('weighing_trailer_required'.tr(), SwsColors.warning);
    final foco =
        _boletoSalida != null ? _pesoSalidaRemolqueFocus : _pesoRemolqueFocus;
    foco.requestFocus();
    return false;
  }

  /// Exige que el peso activo se haya fijado con el botón *Capturar peso*.
  bool _validarCapturaRealizada() {
    if (_objetivoPeso == _ObjetivoPeso.fijado) return true;
    _avisoSimple('weighing_capture_required'.tr(), SwsColors.warning);
    return false;
  }

  // --- Cálculos MODEL.md ---
  double get _pesoTotalEntrada =>
      (double.tryParse(_pesoEntradaCtrl.text) ?? 0) +
      (_remolque ? (double.tryParse(_pesoRemolqueCtrl.text) ?? 0) : 0);

  double get _pesoTotalSalida =>
      (double.tryParse(_pesoSalidaVehiculoCtrl.text) ?? 0) +
      (_remolque ? (double.tryParse(_pesoSalidaRemolqueCtrl.text) ?? 0) : 0);

  double get _pesoNetoDeclarado =>
      double.tryParse(_pesoNetoDeclaradoCtrl.text) ?? 0;

  double get _pesoNetoTotal => _boletoSalida != null
      ? (_pesoTotalEntrada - _pesoTotalSalida)
      : _pesoTotalEntrada;

  double get _pesoDiferencia {
    final pnd = _pesoNetoDeclarado;
    if (pnd == 0) return 0;
    return _pesoNetoTotal - pnd;
  }

  double get _porcentajeDesviacion {
    final pnd = _pesoNetoDeclarado;
    if (pnd == 0) return 0;
    return (_pesoDiferencia / pnd) * 100;
  }

  // ─── Conversión a la medida de facturación (DATOS ADICIONALES) ──────────
  double get _densidadActual => double.tryParse(_densidadCtrl.text.trim()) ?? 0;

  double get _pesoUnidadActual =>
      double.tryParse(_pesoUnidadCtrl.text.trim()) ?? _pesoUnidadProducto ?? 0;

  /// Peso neto base de la conversión. En entrada todavía no hay peso neto
  /// capturable (se conoce al pesar la salida), así que no se calcula nada.
  double get _pesoNetoParaMedida => _boletoSalida != null ? _pesoNetoTotal : 0;

  /// Resultado de la fórmula de la medida elegida.
  double? get _unidadesCalculadas => ConversionMedida.calcular(
        pesoNetoKg: _pesoNetoParaMedida,
        medida: _medida ?? UnidadMedida.kg,
        densidad: _densidadActual,
        pesoUnidad: _pesoUnidadActual,
      );

  /// Litros del peso neto: se persiste siempre que haya densidad, para que los
  /// reportes tengan el volumen aunque la factura se emita en galones.
  double? get _litrosCalculados => ConversionMedida.litros(
        pesoNetoKg: _pesoNetoParaMedida,
        densidad: _densidadActual,
      );

  /// Escribe el resultado en `Unidades` mientras el operador no lo haya
  /// capturado a mano (opción "editable que no se pisa").
  void _recalcularUnidades({bool forzar = false}) {
    if (_unidadesEditadas && !forzar) return;
    _unidadesCtrl.text = ConversionMedida.formatear(_unidadesCalculadas);
  }

  /// Texto de ayuda del campo `Unidades` (fórmula + aviso de factor faltante).
  String get _ayudaUnidades {
    final medida = _medida ?? UnidadMedida.kg;
    if (_pesoNetoParaMedida <= 0) {
      return _boletoSalida == null
          ? 'measure_pending_entry'.tr()
          : 'measure_pending_weight'.tr();
    }
    final calculo = _unidadesCalculadas;
    if (calculo == null) {
      if (medida.requiereDensidad) return 'measure_missing_density'.tr();
      if (medida.requierePesoUnidad) return 'measure_missing_peso_unidad'.tr();
      return ConversionMedida.formula(medida).tr();
    }
    return '${ConversionMedida.formula(medida).tr()} = ${_formatoNumero(calculo)} ${medida.simbolo}';
  }

  /// Formatea con separador de miles para los textos informativos.
  String _formatoNumero(double valor) {
    final s = valor.toStringAsFixed(2);
    final partes = s.split('.');
    final entero = partes.first;
    final buffer = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buffer.write('.');
      buffer.write(entero[i]);
    }
    return '$buffer.${partes.last}';
  }

  void _registrarEntrada() {
    _limpiarFormulario();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('weighing_entry_mode_title'.tr()),
        backgroundColor: SwsColors.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _abrirSelectorSalida() async {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BoletoPendienteDialog(
        onSelected: (b) {
          Navigator.of(ctx).pop();
          _cargarBoletoSalida(b);
        },
      ),
    );
  }

  /// Panel de búsqueda rápida: trae un peso anterior al formulario como copia
  /// editable. El peso original nunca se sobrescribe.
  void _abrirBusquedaPesajes() {
    _alertaAbierta = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BusquedaPesajesDialog(
        onSelected: (w) {
          Navigator.of(ctx).pop();
          _cargarPesajeCopia(w);
        },
      ),
    ).whenComplete(() => _alertaAbierta = false);
  }

  /// Resuelve la entidad del catálogo a partir del id guardado en el pesaje.
  T? _buscarPorId<T>(List<T> items, String? Function(T) id, String? valor) {
    if (valor == null || valor.isEmpty) return null;
    for (final i in items) {
      if (id(i) == valor) return i;
    }
    return null;
  }

  /// Carga un pesaje existente como **copia editable** en modo ENTRADA.
  ///
  /// No entra en modo salida (eso cerraría el boleto original): al guardar se
  /// crea un pesaje nuevo con fecha y hora de ahora.
  void _cargarPesajeCopia(Weighing w) {
    final numero = w.numeroBoleto ?? w.boleto;
    setState(() {
      _boletoSalida = null;
      _origenCopia = w;
      // El número del boleto original no se arrastra: la copia es un pesaje
      // nuevo y recibirá su propia secuencia al guardarse.
      _numeroBoleto = null;
      _camionTexto = w.idVehiculo ?? '';
      _camionSeleccionado = _catalogos.camionByPlaca(_camionTexto);
      _remolque = w.remolque;
      _remolqueTexto = w.remolquePlaca ?? '';
      _remolqueSeleccionado =
          _buscarPorId(_catalogos.trailers, (t) => t.id, w.idRemolque);
      _transporteTexto = w.transporteNombre ?? '';
      _transporteSeleccionado =
          _buscarPorId(_catalogos.transports, (t) => t.id, w.idTransporte);
      _conductorTexto = w.conductorNombre ?? w.idConductor ?? '';
      _conductorSeleccionado = _catalogos.driverByCedula(w.idConductor ?? '');
      _productoTexto = w.productoNombre ?? '';
      _productoSeleccionado =
          _buscarPorId(_catalogos.products, (p) => p.id, w.idProducto);
      _pesoUnidadProducto = _productoSeleccionado?.pesoUnidad;
      _toleranciaProducto = _productoSeleccionado?.tolerancia;
      _almacenTexto = w.almacenNombre ?? '';
      _almacenSeleccionado =
          _buscarPorId(_catalogos.warehouses, (a) => a.id, w.idAlmacen);
      _terceroTexto = w.terceroNombre ?? '';
      _tipoTercero = w.tipoTercero ?? 'CLIENTE';
      _terceroSeleccionado =
          _buscarPorId(_catalogos.thirdParties, (t) => t.id, w.idTercero);
      _idSerieSeleccionada = w.idSerie;
      _balanzaSeleccionada =
          _buscarPorId(_catalogos.scales, (s) => s.id, w.idBalanza);
      _balanzaTexto = _balanzaSeleccionada?.etiqueta ?? w.balanzaNombre ?? '';
      _confirmados[_idxBalanza] = _balanzaSeleccionada != null;

      _pesoEntradaCtrl.text = w.pesoEntradaVehiculo.toStringAsFixed(2);
      _pesoRemolqueCtrl.text = (_remolque && w.pesoEntradaRemolque != null)
          ? w.pesoEntradaRemolque!.toStringAsFixed(2)
          : '';
      _pesoSalidaVehiculoCtrl.clear();
      _pesoSalidaRemolqueCtrl.clear();
      _pesoNetoDeclaradoCtrl.text = w.pesoNetoDeclarado != null
          ? w.pesoNetoDeclarado!.toStringAsFixed(2)
          : '';
      _documentoCtrl.text = w.documento ?? '';
      _guiaSunagroCtrl.text = w.guiaSunagro ?? '';
      _asignarMedida(ConversionMedida.desdeTexto(w.medida));
      _unidadesEditadas = w.unidades != null;
      _densidadCtrl.text =
          w.densidad != null ? w.densidad!.toStringAsFixed(2) : '';
      _unidadesCtrl.text =
          w.unidades != null ? w.unidades!.toStringAsFixed(2) : '';
      _observacionesCtrl.text = w.observaciones ?? '';
      _fleteCtrl.text = w.flete ?? '';
      _costoFleteCtrl.text =
          w.costoFlete != null ? w.costoFlete!.toStringAsFixed(2) : '';
      // La copia arranca como una captura nueva: hay que volver a capturar.
      _reiniciarCapturaGuiada();
      _confirmados[_idxPesoEntrada] = false;
      if (_remolque) _confirmados[_idxPesoRemolque] = false;
    });
    _avisoSimple(AppTranslations.tr('weighing_copy_loaded', args: [numero]),
        SwsColors.warning);
  }

  Future<void> _abrirSelectorImpresion() async {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BoletoImpresionDialog(
        ultimoBoletoId: _ultimoBoletoId,
        ultimoNumeroBoleto: _ultimoNumeroBoleto,
        onImprimir: (boletoId, numeroBoleto, formato) {
          Navigator.of(ctx).pop();
          _reimprimirTicket(boletoId, numeroBoleto, formato: formato);
        },
      ),
    );
  }

  void _cargarBoletoSalida(Weighing b) {
    setState(() {
      _boletoSalida = b;
      _numeroBoleto = b.numeroBoleto ?? b.boleto;
      _camionTexto = b.idVehiculo ?? '';
      _remolqueTexto = b.remolquePlaca ?? '';
      _transporteTexto = b.transporteNombre ?? '';
      _conductorTexto = b.conductorNombre ?? '';
      _productoTexto = b.productoNombre ?? '';
      _almacenTexto = b.almacenNombre ?? '';
      _balanzaTexto = b.balanzaNombre ?? '';
      _terceroTexto = b.terceroNombre ?? '';
      _remolque = b.remolque;
      _pesoEntradaCtrl.text = b.pesoEntradaVehiculo.toStringAsFixed(2);
      _pesoRemolqueCtrl.text =
          _remolque ? (b.pesoEntradaRemolque ?? 0).toStringAsFixed(2) : '';
      _pesoSalidaVehiculoCtrl.clear();
      _pesoSalidaRemolqueCtrl.clear();
      _pesoNetoDeclaradoCtrl.text = b.pesoNetoDeclarado != null
          ? b.pesoNetoDeclarado!.toStringAsFixed(2)
          : '';
      _documentoCtrl.text = b.documento ?? '';
      _guiaSunagroCtrl.text = b.guiaSunagro ?? '';
      _asignarMedida(ConversionMedida.desdeTexto(b.medida));
      _unidadesEditadas = b.unidades != null;
      _observacionesCtrl.text = b.observaciones ?? '';
      _fleteCtrl.text = b.flete ?? '';
      _costoFleteCtrl.text =
          b.costoFlete != null ? b.costoFlete!.toStringAsFixed(2) : '';
      _densidadCtrl.text =
          b.densidad != null ? b.densidad!.toStringAsFixed(2) : '';
      _unidadesCtrl.text =
          b.unidades != null ? b.unidades!.toStringAsFixed(2) : '';
      _tipoTercero = b.tipoTercero ?? 'CLIENTE';
      _reiniciarCapturaGuiada();
      _balanzaSeleccionada = null;
      _balanzaTexto = '';
      _aplicarBalanzaPorDefecto(modoSalida: true);
      _balanzaTexto = _balanzaSeleccionada?.etiqueta ?? '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cargado Boleto $_numeroBoleto para pesaje de SALIDA'),
        backgroundColor: SwsColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _limpiarFormulario() {
    setState(() {
      _boletoSalida = null;
      _origenCopia = null;
      _tieneDatosSinGuardar = false;
      _pesoEntradaCtrl.clear();
      _pesoRemolqueCtrl.clear();
      _pesoSalidaVehiculoCtrl.clear();
      _pesoSalidaRemolqueCtrl.clear();
      _pesoNetoDeclaradoCtrl.clear();
      _documentoCtrl.clear();
      _guiaSunagroCtrl.clear();
      _asignarMedida(null);
      _unidadesCtrl.clear();
      _densidadCtrl.clear();
      _pesoUnidadCtrl.clear();
      _pesoUnidadProducto = null;
      _toleranciaProducto = null;
      _unidadesEditadas = false;
      _reiniciarCapturaGuiada();
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
      _aplicarBalanzaPorDefecto(modoSalida: false);
      _balanzaTexto = _balanzaSeleccionada?.etiqueta ?? '';
      _fotosCamion = [];
      _fotosRemolque = [];
      _numeroBoleto = null;
      _fechaActual = DateTime.now();
      for (var i = 0; i < _confirmados.length; i++) {
        _confirmados[i] = false;
      }
    });
    _marcarDatosSinGuardarGlobal(false);
    _cargarSeries();
  }

  void _imprimirActual({String formato = 'PDF'}) {
    if (_ultimoBoletoId != null) {
      _reimprimirTicket(_ultimoBoletoId!, _ultimoNumeroBoleto ?? 'Boleto',
          formato: formato);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('weighing_save_first'.tr())),
      );
    }
  }

  Future<void> _reimprimirTicket(String boleto, String nombreBoleto,
      {String formato = 'PDF'}) async {
    try {
      final preset = await di.sl<LocalStorage>().getPrinterPreset();
      final repo = di.sl<WeighingRepository>();
      final response = formato == 'TXT'
          ? await repo.getTicketTxt(boleto, tipoTicket: preset.tipoTicket)
          : await repo.getTicketPdf(
              boleto,
              boletosPorHoja: preset.boletosPorHoja,
              tamanoPapel: preset.tamanoPapel,
              orientacion: preset.orientacion,
              mostrarEncabezado: preset.mostrarEncabezado,
              mostrarDetalles: preset.mostrarDetalles,
              tipoTicket: preset.tipoTicket,
            );
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un $formato válido.');
      }
      final extension = formato == 'TXT' ? 'txt' : 'pdf';
      final ruta = await SaveFileUtils.save(
          bytes, 'ticket_$nombreBoleto.$extension',
          subcarpeta: 'tickets');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ticket ($formato) guardado en: $ruta'),
              backgroundColor: SwsColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al generar ticket: $e'),
              backgroundColor: SwsColors.danger),
        );
      }
    }
  }

  /// F4 / Enter: valida, pide la confirmación final y guarda.
  Future<void> _onSave() async {
    if (_alertaAbierta || _guardandoPesaje) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('weighing_min_fields_required'.tr()),
          backgroundColor: SwsColors.warning,
        ),
      );
      return;
    }

    // ── MODO SALIDA (Cierre directo de boleto) ──────────────────────────────
    if (_boletoSalida != null) {
      final pesoSalidaVeh = double.tryParse(_pesoSalidaVehiculoCtrl.text) ?? 0;
      if (pesoSalidaVeh <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('weighing_exit_weight_prompt'.tr()),
            backgroundColor: SwsColors.warning,
          ),
        );
        return;
      }
      if (!_validarPesoRemolqueObligatorio()) return;
      if (!_validarCapturaRealizada()) return;
      if (!await _confirmarGuardado()) return;
      if (!mounted) return;
      _guardar();
      return;
    }

    // ── MODO ENTRADA (Creación de pesaje nuevo) ─────────────────────────────
    if (!_validarPesoRemolqueObligatorio()) return;
    if (!_validarCapturaRealizada()) return;
    if (!await _confirmarGuardado()) return;
    if (!mounted) return;
    _guardar();
  }

  /// Envía el pesaje a la API (ya validado y confirmado por el operador).
  void _guardar() {
    // ── MODO SALIDA (Cierre directo de boleto) ──────────────────────────────
    if (_boletoSalida != null) {
      final pesoSalidaVeh = double.tryParse(_pesoSalidaVehiculoCtrl.text) ?? 0;
      if (!_validarPesoRemolqueObligatorio()) return;
      final unidades = double.tryParse(_unidadesCtrl.text.trim());
      final litros = _litrosCalculados ??
          (_medida == UnidadMedida.litros ? unidades : null);
      final payload = <String, dynamic>{
        'peso_salida_vehiculo': pesoSalidaVeh,
        if (_remolque && _pesoSalidaRemolqueCtrl.text.isNotEmpty)
          'peso_salida_remolque': double.tryParse(_pesoSalidaRemolqueCtrl.text),
        if (_pesoNetoDeclaradoCtrl.text.isNotEmpty)
          'peso_neto_declarado': double.tryParse(_pesoNetoDeclaradoCtrl.text),
        'es_peso_manual': _esPesoManual,
        if (_observacionesCtrl.text.trim().isNotEmpty)
          'observaciones': _observacionesCtrl.text.trim(),
        if (_documentoCtrl.text.trim().isNotEmpty)
          'documento': _documentoCtrl.text.trim(),
        if (_guiaSunagroCtrl.text.trim().isNotEmpty)
          'guia_sunagro': _guiaSunagroCtrl.text.trim(),
        if (_medida != null) 'medida': _medida!.etiquetaPersistida,
        if (_fleteCtrl.text.trim().isNotEmpty) 'flete': _fleteCtrl.text.trim(),
        if (_costoFleteCtrl.text.isNotEmpty)
          'costo_flete': double.tryParse(_costoFleteCtrl.text),
        if (_densidadCtrl.text.isNotEmpty)
          'densidad': double.tryParse(_densidadCtrl.text),
        if (unidades != null) 'unidades': unidades,
        if (litros != null) 'litros': litros,
      };
      context
          .read<WeighingBloc>()
          .add(CloseWeighingEvent(_boletoSalida!.boleto, payload));
      return;
    }

    // ── MODO ENTRADA (Creación de pesaje nuevo) ─────────────────────────────
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
      idSerie: _idSerieSeleccionada,
      fechaHoraEntrada: now,
      pesoEntradaVehiculo: double.tryParse(_pesoEntradaCtrl.text) ?? 0,
      pesoEntradaRemolque:
          _remolque ? double.tryParse(_pesoRemolqueCtrl.text) : null,
      pesoNetoDeclarado: _pesoNetoDeclaradoCtrl.text.isNotEmpty
          ? double.tryParse(_pesoNetoDeclaradoCtrl.text)
          : null,
      documento: _documentoCtrl.text.trim().isNotEmpty
          ? _documentoCtrl.text.trim()
          : null,
      guiaSunagro: _guiaSunagroCtrl.text.trim().isNotEmpty
          ? _guiaSunagroCtrl.text.trim()
          : null,
      medida: _medida?.etiquetaPersistida,
      flete: _fleteCtrl.text.trim().isNotEmpty ? _fleteCtrl.text.trim() : null,
      costoFlete: double.tryParse(_costoFleteCtrl.text),
      densidad: double.tryParse(_densidadCtrl.text),
      litros: _litrosCalculados ??
          (_medida == UnidadMedida.litros
              ? double.tryParse(_unidadesCtrl.text)
              : null),
      unidades: double.tryParse(_unidadesCtrl.text),
      observaciones: _observacionesCtrl.text.trim().isNotEmpty
          ? _observacionesCtrl.text.trim()
          : null,
      createdAt: now,
      updatedAt: now,
    );

    final adicionales = <String, dynamic>{
      'remolque_placa':
          _remolque ? (_remolqueSeleccionado?.placa ?? _remolqueTexto) : null,
      'transporte_nombre':
          _transporteSeleccionado?.razonSocial ?? _transporteTexto,
      'conductor_nombre': _conductorTexto,
      'producto_nombre': _productoSeleccionado?.nombre ?? _productoTexto,
      'almacen_nombre': _almacenSeleccionado?.nombre ?? _almacenTexto,
      'balanza_nombre': _balanzaSeleccionada?.descripcion ?? _balanzaTexto,
      'tercero_nombre': _terceroSeleccionado?.razonSocial ?? _terceroTexto,
      'es_peso_manual': _esPesoManual,
      if (_idSerieSeleccionada != null) 'id_serie': _idSerieSeleccionada,
    };

    context
        .read<WeighingBloc>()
        .add(CreateWeighingEvent(weighing, adicionales: adicionales));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WeighingBloc, WeighingState>(
      listener: (context, state) {
        if (state is WeighingLoading) {
          setState(() => _guardandoPesaje = true);
        } else if (state is WeighingCreated) {
          final boletoId = state.weighing.boleto;
          final numeroVisible = state.weighing.numeroBoleto ?? 'Boleto';
          _ultimoBoletoId = boletoId;
          _ultimoNumeroBoleto = numeroVisible;
          _numeroBoleto = numeroVisible;
          setState(() => _guardandoPesaje = false);
          _subirFotos(boletoId);
          _limpiarFormulario();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Pesaje de Entrada $numeroVisible guardado correctamente'),
                backgroundColor: SwsColors.success,
                duration: const Duration(seconds: 3),
              ),
            );
            _alertaImprimir(numeroVisible);
          }
        } else if (state is WeighingClosed) {
          final numeroVisible = state.weighing.numeroBoleto ?? 'Boleto';
          _ultimoBoletoId = state.weighing.boleto;
          _ultimoNumeroBoleto = numeroVisible;
          setState(() => _guardandoPesaje = false);
          _limpiarFormulario();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Salida del pesaje $numeroVisible registrada exitosamente'),
                backgroundColor: SwsColors.success,
                duration: const Duration(seconds: 3),
              ),
            );
            _alertaImprimir(numeroVisible);
          }
        } else if (state is WeighingError) {
          setState(() => _guardandoPesaje = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: SwsColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          // Estados globales ajenos a esta pantalla (listado, sync, detalle de
          // boleto, anulación): solo liberamos el bloqueo del botón Guardar.
          setState(() => _guardandoPesaje = false);
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
    var ok = 0;
    for (final entrada in todas) {
      try {
        await api.uploadImage(boleto, entrada.foto.bytes, entrada.foto.nombre,
            tipo: entrada.tipo);
        ok++;
      } catch (_) {}
    }
    final total = todas.length;
    if (ok < total && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No se pudieron subir las fotos del pesaje ($ok de $total). Verifique la conexión y vuelva a intentar al cerrar el boleto.'),
          backgroundColor: SwsColors.warning,
        ),
      );
    }
  }

  Widget _buildForm(BuildContext context, CatalogData data) {
    if (!identical(data, _catalogos)) _catalogos = data;
    final trailers = data.trailersActivos;
    final terceros = data.tercerosPorTipo(_tipoTercero);
    // A partir de 1200px usamos 3 columnas; debajo, layout apilado.
    final isWide = MediaQuery.sizeOf(context).width > 1200;

    return Column(
      children: [
        _QuickActionBar(
          onBuscar: _abrirBusquedaPesajes,
          onEntrada: _registrarEntrada,
          onSalida: _abrirSelectorSalida,
          onGuardar: _onSave,
          onCancelar: _limpiarFormulario,
          onImprimir: _abrirSelectorImpresion,
          onSalir: () => Navigator.of(context).pop(),
          puedeAnular: false,
          guardando: _guardandoPesaje,
          modoSalida: _boletoSalida != null,
        ),
        if (_boletoSalida != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: SwsColors.success.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.output, color: SwsColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MODO SALIDA — Cierre del Boleto: ${_numeroBoleto ?? _boletoSalida!.boleto} ($_camionTexto)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: SwsColors.success,
                        fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text('weighing_back_to_entry'.tr()),
                  onPressed: _limpiarFormulario,
                ),
              ],
            ),
          ),
        if (_origenCopia != null) _buildAvisoCopia(_origenCopia!),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Form(
              key: _formKey,
              child: Focus(
                onKeyEvent: _manejarFlechas,
                child: isWide
                    ? _buildThreeColumnLayout(context, data, trailers, terceros)
                    : _buildSingleColumnLayout(
                        context, data, trailers, terceros),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT DE 3 COLUMNAS
  //   [LECTURA DE PESO] | [DATOS DEL PESAJE + ADICIONALES + OBS] | [RESUMEN + FOTOS]
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildThreeColumnLayout(
    BuildContext context,
    CatalogData data,
    List<Trailer> trailers,
    List<ThirdParty> terceros,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── COLUMNA IZQUIERDA: LECTURA DE PESO ────────────────────────────
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'LECTURA DE PESO',
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

        // ── COLUMNA CENTRAL: DATOS DEL PESAJE + ADICIONALES + OBS ─────────
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'DATOS DEL PESAJE',
                icon: Icons.assignment,
                children: _buildDatosSection(context, data, trailers, terceros),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // ── COLUMNA DERECHA: RESUMEN + FOTOS ──────────────────────────────
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Widget _buildSingleColumnLayout(
    BuildContext context,
    CatalogData data,
    List<Trailer> trailers,
    List<ThirdParty> terceros,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'LECTURA DE PESO',
          icon: Icons.monitor_weight,
          children: _buildLecturaSection(context),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'DATOS DEL PESAJE',
          icon: Icons.assignment,
          children: _buildDatosSection(context, data, trailers, terceros),
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

  List<Widget> _buildDatosSection(BuildContext context, CatalogData data,
      List<Trailer> trailers, List<ThirdParty> terceros) {
    final enModoSalida = _boletoSalida != null;

    return [
      Row(
        children: [
          Expanded(
            child: _HeaderInfoRow(
              label: 'Serie - Boleto',
              value: _numeroBoleto ??
                  (_serieActiva != null
                      ? '${_serieActiva!['prefijo']}${(_serieActiva!['siguiente'] as int? ?? 1).toString().padLeft(_serieActiva!['digitos'] as int? ?? 6, '0')} (Próx.)'
                      : 'PENDIENTE'),
              icon: Icons.confirmation_number_outlined,
            ),
          ),
          if (_series.length > 1 && !enModoSalida) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<String>(
                value: _idSerieSeleccionada,
                isDense: true,
                underline: const SizedBox(),
                items: _series.map<DropdownMenuItem<String>>((s) {
                  final id = s['id_serie']?.toString() ?? '';
                  final pref = s['prefijo']?.toString() ?? '';
                  final nom = s['nombre']?.toString() ?? pref;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text('Serie: $pref ($nom)',
                        style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _idSerieSeleccionada = val;
                      final sel = _series.firstWhere(
                          (s) => s['id_serie']?.toString() == val,
                          orElse: () => null);
                      if (sel != null) {
                        _serieActiva = Map<String, dynamic>.from(sel);
                      }
                    });
                  }
                },
              ),
            ),
          ],
        ],
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
        initialValue: _camionTexto,
        onFocusNodeReady: (node) => _focos[_idxCamion] = node,
        onSelected: (v) => setState(() {
          _camionSeleccionado = v;
          _confirmarCampo(_idxCamion);
          final tid = v.transporteId;
          if (tid != null && tid.isNotEmpty) {
            final t = data.transports.where((x) => x.id == tid).firstOrNull;
            _transporteSeleccionado = t;
            _transporteTexto = t?.razonSocial ?? '';
            if (t != null) _confirmarCampo(_idxTransporte);
          }
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
        title: Text('weighing_has_trailer'.tr(),
            style: const TextStyle(fontSize: 13.5)),
        value: _remolque,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        onChanged: enModoSalida
            ? null
            : (v) => setState(() {
                  _remolque = v;
                  _reiniciarCapturaGuiada();
                  if (!v) {
                    _remolqueSeleccionado = null;
                    _pesoRemolqueCtrl.clear();
                    _pesoSalidaRemolqueCtrl.clear();
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
          initialValue: _remolqueTexto,
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
        initialValue: _transporteTexto,
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
        initialValue: _conductorTexto,
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
                  CrearCampoSpec(
                      key: 'nombre_completo',
                      label: 'Nombre completo',
                      icon: Icons.person_outline,
                      requerido: true,
                      initial: _pareceCedula(_conductorTexto)
                          ? null
                          : _conductorTexto),
                  CrearCampoSpec(
                      key: 'cedula_dni',
                      label: 'Cédula / DNI',
                      icon: Icons.badge_outlined,
                      requerido: true,
                      initial: _pareceCedula(_conductorTexto)
                          ? _conductorTexto
                          : null),
                  const CrearCampoSpec(
                      key: 'telefono',
                      label: 'Teléfono',
                      icon: Icons.phone_outlined),
                  const CrearCampoSpec(
                      key: 'licencia_conducir',
                      label: 'Licencia de conducir',
                      icon: Icons.credit_card_outlined),
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
        initialValue: _productoTexto,
        onFocusNodeReady: (node) => _focos[_idxProducto] = node,
        onSelected: (p) => setState(() {
          _productoSeleccionado = p;
          _confirmarCampo(_idxProducto);
          _pesoUnidadProducto = p.pesoUnidad;
          _toleranciaProducto = p.tolerancia;
          if (p.densidadEstandar != null && _densidadCtrl.text.trim().isEmpty) {
            _densidadCtrl.text = p.densidadEstandar!.toStringAsFixed(2);
          }
          if (p.pesoUnidad != null) {
            _pesoUnidadCtrl.text = p.pesoUnidad!.toStringAsFixed(2);
          }
          final medidaProducto =
              ConversionMedida.desdeUnidadProducto(p.unidadMedida);
          if (_medida == null) _asignarMedida(medidaProducto);
          _unidadesEditadas = false;
          _recalcularUnidades(forzar: true);
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
        initialValue: _almacenTexto,
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
        initialValue: _balanzaTexto,
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
              items: [
                DropdownMenuItem(
                    value: 'CLIENTE', child: Text('third_customer'.tr())),
                DropdownMenuItem(
                    value: 'PROVEEDOR', child: Text('third_supplier'.tr())),
                DropdownMenuItem(
                    value: 'AMBOS', child: Text('weighing_both'.tr())),
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
              search: (t) =>
                  '${t.razonSocial} ${t.codigo ?? ''} ${t.identificacionFiscal ?? ''} ${t.tipo}',
              required: false,
              fieldName: 'Razón Social',
              icon: Icons.business,
              hint: 'Nombre del tercero',
              initialValue: _terceroTexto,
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
                        const CrearCampoSpec(
                            key: 'razon_social',
                            label: 'Razón social',
                            icon: Icons.badge_outlined,
                            requerido: true,
                            precargarTexto: true),
                        CrearCampoSpec(
                            key: 'tipo',
                            label: 'Tipo',
                            icon: Icons.category_outlined,
                            tipo: CrearCampoTipo.dropdown,
                            opciones: ['CLIENTE', 'PROVEEDOR', 'AMBOS'],
                            requerido: true,
                            initial: _tipoTercero),
                        const CrearCampoSpec(
                            key: 'codigo',
                            label: 'Código',
                            icon: Icons.numbers_outlined),
                        const CrearCampoSpec(
                            key: 'identificacion_fiscal',
                            label: 'RIF / Identificación fiscal',
                            icon: Icons.badge_outlined),
                        const CrearCampoSpec(
                            key: 'telefono',
                            label: 'Teléfono',
                            icon: Icons.phone_outlined),
                        const CrearCampoSpec(
                            key: 'direccion',
                            label: 'Dirección',
                            icon: Icons.place_outlined,
                            tipo: CrearCampoTipo.multilinea),
                        const CrearCampoSpec(
                            key: 'email',
                            label: 'Email',
                            icon: Icons.email_outlined,
                            tipo: CrearCampoTipo.email),
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

  /// Lectura de pesos.
  /// Aviso de avance: la cabina ya está pesada y falta la captura del remolque.
  /// Aviso de que el formulario tiene una **copia** de otro pesaje: los campos
  /// son editables, pero al guardar se registra un pesaje nuevo con la fecha de
  /// hoy y el original queda intacto.
  Widget _buildAvisoCopia(Weighing origen) {
    final numero = origen.numeroBoleto ?? origen.boleto;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: SwsColors.warning.withValues(alpha: 0.18),
      child: Row(
        children: [
          const Icon(Icons.content_copy, color: SwsColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppTranslations.tr('weighing_copy_title', args: [numero]),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SwsColors.warning,
                      fontSize: 13),
                ),
                Text(
                  'weighing_copy_hint'.tr(),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('weighing_copy_discard'.tr(),
                style: const TextStyle(fontSize: 12)),
            onPressed: _limpiarFormulario,
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoAvanceRemolque() {
    if (!_guiaRemolque) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SwsColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SwsColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_filled_outlined,
              size: 20, color: SwsColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${'weighing_cabina_registered'.tr()}: '
                  '${_formatoNumero(_pesoCabinaActual)} kg',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'weighing_trailer_advance'.tr(),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'weighing_trailer_advance_hint'.tr(),
                  style:
                      const TextStyle(fontSize: 11.5, color: SwsColors.gray600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'F3',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: SwsColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLecturaSection(BuildContext context) {
    final enModoSalida = _boletoSalida != null;

    return [
      if (_hayBascula)
        ScaleMonitorWidget(
          client: _scaleClient,
          label: _balanzaSeleccionada?.descripcion ?? 'Báscula',
          balanzaId: _balanzaSeleccionada?.id,
          balanzaDescripcion: _balanzaSeleccionada?.descripcion,
          initialWeight: enModoSalida
              ? (double.tryParse(_pesoSalidaVehiculoCtrl.text) ?? 0)
              : (double.tryParse(_pesoEntradaCtrl.text) ?? 0),
          onPesoLeido: (peso) {
            setState(() {
              _ctrlActivoPeso?.text = peso.toStringAsFixed(2);
              _recalcularUnidades();
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
              const Icon(Icons.edit_note, size: 18, color: SwsColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'weighing_manual_weight_no_scale'.tr(),
                  style: const TextStyle(
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
        readOnly: !_esPesoManual || enModoSalida,
        onChanged: (valor) {
          _desconfirmarCampo(_idxPesoEntrada);
        },
        onFieldSubmitted: (_) {
          _confirmarCampo(_idxPesoEntrada);
          _avanzarAlSiguienteCampo(_idxPesoEntrada);
        },
        decoration: InputDecoration(
          labelText: 'Peso Entrada Vehículo (kg) *',
          prefixIcon: !_esPesoManual || enModoSalida
              ? const Icon(Icons.link)
              : const Icon(Icons.monitor_weight),
          helperText: enModoSalida
              ? 'Peso fijado a la entrada'
              : (_esPesoManual
                  ? 'Registro manual (solo Supervisor/Admin)'
                  : 'Peso registrado por la báscula: no se puede editar'),
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) => Validators.positiveNumber(v, 'Peso Entrada'),
      ),
      if (_remolque && !enModoSalida) ...[
        const SizedBox(height: 8),
        _buildAvisoAvanceRemolque(),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('peso_remolque_field'),
          controller: _pesoRemolqueCtrl,
          focusNode: _pesoRemolqueFocus,
          onChanged: (_) {
            setState(() => _recalcularUnidades());
          },
          decoration: InputDecoration(
            labelText: 'Peso Remolque Entrada (kg) *',
            hintText: _guiaRemolque
                ? 'weighing_trailer_capture_here'.tr()
                : 'Se sugiere la tara del remolque',
            prefixIcon: const Icon(Icons.fitness_center),
            filled: _guiaRemolque,
            fillColor: SwsColors.accent.withValues(alpha: 0.08),
            isDense: true,
            enabledBorder: _guiaRemolque
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: SwsColors.accent, width: 1.6),
                  )
                : null,
            focusedBorder: _guiaRemolque
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: SwsColors.accent, width: 2),
                  )
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if (!_remolque) return null;
            if ((double.tryParse(v ?? '') ?? 0) <= 0) {
              return 'weighing_trailer_required'.tr();
            }
            return null;
          },
        ),
      ],
      if (enModoSalida) ...[
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('peso_salida_field'),
          controller: _pesoSalidaVehiculoCtrl,
          focusNode: _pesoSalidaVehiculoFocus,
          readOnly: !_esPesoManual,
          onChanged: (valor) {
            setState(() => _recalcularUnidades());
          },
          decoration: InputDecoration(
            labelText: 'Peso Salida Vehículo (kg) *',
            prefixIcon: const Icon(Icons.output, color: SwsColors.success),
            helperText: _esPesoManual
                ? 'Registro manual de salida (solo Supervisor/Admin)'
                : 'Lectura de balanza para salida',
            isDense: true,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) =>
              enModoSalida ? Validators.positiveNumber(v, 'Peso Salida') : null,
        ),
        if (_remolque) ...[
          const SizedBox(height: 8),
          _buildAvisoAvanceRemolque(),
          const SizedBox(height: 10),
          TextFormField(
            controller: _pesoSalidaRemolqueCtrl,
            focusNode: _pesoSalidaRemolqueFocus,
            onChanged: (_) {
              setState(() => _recalcularUnidades());
            },
            decoration: InputDecoration(
              labelText: 'Peso Salida Remolque (kg) *',
              hintText: 'Capture el peso del remolque',
              prefixIcon: const Icon(Icons.fitness_center),
              filled: _guiaRemolque,
              fillColor: SwsColors.accent.withValues(alpha: 0.08),
              isDense: true,
              enabledBorder: _guiaRemolque
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: SwsColors.accent, width: 1.6),
                    )
                  : null,
              focusedBorder: _guiaRemolque
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: SwsColors.accent, width: 2),
                    )
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => _remolque && (double.tryParse(v ?? '') ?? 0) <= 0
                ? 'weighing_trailer_required'.tr()
                : null,
          ),
        ],
      ],
      const SizedBox(height: 10),
      _CapturarPesoButton(
        onTap: _capturarPeso,
        etiqueta: _etiquetaCapturarPeso,
        pendiente: _objetivoPeso != _ObjetivoPeso.fijado,
      ),
      if (_puedePesoManual && _hayBascula && !enModoSalida) ...[
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('weighing_manual_record'.tr(),
              style: const TextStyle(fontSize: 12.5)),
          subtitle: Text('weighing_supervisor_admin_only'.tr(),
              style: const TextStyle(fontSize: 11)),
          value: _esPesoManual,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _esPesoManual = v),
        ),
      ],
      const SizedBox(height: 8),
      _WeightTable(
        pesoEntrada: double.tryParse(_pesoEntradaCtrl.text) ?? 0,
        pesoRemolqueEntrada:
            _remolque ? double.tryParse(_pesoRemolqueCtrl.text) : null,
        pesoSalida:
            enModoSalida ? double.tryParse(_pesoSalidaVehiculoCtrl.text) : null,
        pesoRemolqueSalida: (enModoSalida && _remolque)
            ? double.tryParse(_pesoSalidaRemolqueCtrl.text)
            : null,
        pesoNetoDeclarado: double.tryParse(_pesoNetoDeclaradoCtrl.text),
      ),
      _buildTablaTolerancia(),
    ];
  }

  /// Tabla *CONTROL DE TOLERANCIA Y DECLARADO* (MODEL.md), debajo de los pesos.
  ///
  /// `PNT = PTE - PTS`, `PDF = PNT - PND`, `PDV = PDF / PND`. Cuando no hay
  /// PND o tolerancia se muestra `-` en vez de `#¡DIV/0!` / `#¡VALOR!`.
  Widget _buildTablaTolerancia() {
    final enModoSalida = _boletoSalida != null;
    final pte = _pesoTotalEntrada;
    final pts = enModoSalida ? _pesoTotalSalida : 0.0;
    final pnt = _pesoNetoTotal;
    final pnd = double.tryParse(_pesoNetoDeclaradoCtrl.text.trim()) ?? 0;
    final pdf = pnt - pnd;
    final pdv = pnd == 0 ? null : (pdf / pnd * 100);
    final tolerancia = (_toleranciaProducto ?? 0).clamp(0, 100).toDouble();

    // Rango de aceptación comercial: PND ± tolerancia %.
    final rango =
        tolerancia > 0 && pnd > 0 ? (pnd * tolerancia / 100).abs() : null;
    String? estado;
    Color? estadoColor;
    if (rango != null) {
      final dentro = pdf.abs() <= rango + 0.0001;
      estado = dentro ? 'DENTRO' : (pdf > 0 ? 'SOBRE' : 'BAJO');
      estadoColor = dentro ? SwsColors.success : SwsColors.danger;
    }

    Widget fila(String concepto, String valor,
        {Color? color, bool fuerte = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                concepto,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
                  color: fuerte ? SwsColors.gray600 : null,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    String fechaTxt(DateTime? f) =>
        f == null ? '-' : app_dates.DateUtils.formatDateTime(f.toLocal());
    final fechaEntrada = fechaTxt(_boletoSalida?.fechaHoraEntrada);
    final fechaSalida = fechaTxt(_boletoSalida?.fechaHoraSalida);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: SwsColors.gray200.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SwsColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('CONTROL DE PESOS Y TOLERANCIA',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SwsColors.gray600)),
          const SizedBox(height: 4),
          // Encabezado de la tabla de lectura
          const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('CONCEPTO',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: SwsColors.gray500)),
              ),
              Expanded(
                flex: 2,
                child: Text('FECHA / HORA',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: SwsColors.gray500)),
              ),
            ],
          ),
          const Divider(height: 8, color: SwsColors.gray200),
          fila('Entrada', fechaEntrada),

          if (enModoSalida) fila('Salida', fechaSalida),
          fila('Peso Camión (kg)', NumberUtils.formatKg(_pesoCabinaActual)),
          if (_remolque)
            fila('Peso Remolque (kg)',
                NumberUtils.formatKg(_pesoRemolqueActual)),
          fila(
              'Peso Total (kg)', NumberUtils.formatKg(enModoSalida ? pts : pte),
              fuerte: true),
          const Divider(height: 10, color: SwsColors.gray200),
          fila('PESO NETO TOTAL (PNT)', NumberUtils.formatKg(pnt),
              fuerte: true),
          const SizedBox(height: 8),
          const Text('CONTROL DE TOLERANCIA Y DECLARADO',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SwsColors.gray600)),
          const SizedBox(height: 4),
          fila('Peso Neto Declarado (PND)', NumberUtils.formatKg(pnd)),
          fila('Diferencia de Peso (PDF)', NumberUtils.formatKg(pdf)),
          fila('% Desviación (PDV)',
              pdv == null ? '-' : '${pdv.toStringAsFixed(2)} %'),
          fila('Tolerancia Producto (%)',
              tolerancia == 0 ? '-' : '${tolerancia.toStringAsFixed(2)} %'),
          fila('Estado Tolerancia', estado ?? '-',
              color: estadoColor, fuerte: estado != null),
          if (rango != null)
            fila(
                'Rango aceptado (PND ± tol.)',
                '${NumberUtils.formatKg(pnd - rango)} — '
                    '${NumberUtils.formatKg(pnd + rango)}'),
        ],
      ),
    );
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
            child: DropdownButtonFormField<UnidadMedida>(
              key: ValueKey('medida_field_$_medidaSeed'),
              focusNode: _medidaFocus,
              initialValue: _medida,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Medida',
                prefixIcon: Icon(Icons.straighten_outlined),
                isDense: true,
              ),
              items: [
                for (final m in UnidadMedida.values)
                  DropdownMenuItem(value: m, child: Text(m.etiqueta)),
              ],
              onChanged: (m) {
                setState(() {
                  _asignarMedida(m, refrescarCampo: false);
                  _unidadesEditadas = false;
                  if (m != null &&
                      m.requiereDensidad &&
                      _densidadCtrl.text.trim().isEmpty &&
                      _productoSeleccionado?.densidadEstandar != null) {
                    _densidadCtrl.text = _productoSeleccionado!
                        .densidadEstandar!
                        .toStringAsFixed(2);
                  }
                  _recalcularUnidades(forzar: true);
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _unidadesCtrl,
              focusNode: _unidadesFocus,
              onChanged: (_) {
                _unidadesEditadas = true;
                _desconfirmarCampo(_idxUnidades);
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Unidades',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                helperText: _ayudaUnidades,
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: 'measure_recalculate'.tr(),
                  icon: const Icon(Icons.calculate_outlined, size: 20),
                  onPressed: () => setState(() {
                    _unidadesEditadas = false;
                    _recalcularUnidades(forzar: true);
                  }),
                ),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _densidadCtrl,
              focusNode: _densidadFocus,
              readOnly: (_medida ?? UnidadMedida.kg) != UnidadMedida.litros &&
                  (_medida ?? UnidadMedida.kg) != UnidadMedida.galones,
              onChanged: (_) {
                _desconfirmarCampo(_idxDensidad);
                setState(() => _recalcularUnidades());
              },
              decoration: InputDecoration(
                labelText: 'Densidad (kg/L)',
                prefixIcon: const Icon(Icons.speed_outlined),
                helperText: (_medida ?? UnidadMedida.kg).requiereDensidad
                    ? 'measure_density_hint'.tr()
                    : 'measure_density_not_used'.tr(),
                helperMaxLines: 2,
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
      if (_medida != null && _medida!.requierePesoUnidad) ...[
        const SizedBox(height: 10),
        TextFormField(
          controller: _pesoUnidadCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Peso por unidad (kg)',
            prefixIcon: const Icon(Icons.scale_outlined),
            helperText: _pesoUnidadActual > 0
                ? 'measure_peso_unidad_from_product'.tr()
                : 'measure_peso_unidad_missing'.tr(),
            helperMaxLines: 2,
            isDense: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
        buildCounter: (context,
                {required currentLength,
                required isFocused,
                required maxLength}) =>
            null,
      ),
    ];
  }

  List<Widget> _buildResumenSection(CatalogData data) {
    final enModoSalida = _boletoSalida != null;
    final ptsRem = _remolque
        ? double.tryParse(_pesoSalidaRemolqueCtrl.text) ??
            double.tryParse(_pesoRemolqueCtrl.text)
        : null;

    return [
      _ResumenRow(
        label: 'Serie - Boleto',
        value: _numeroBoleto ??
            (_serieActiva != null
                ? '${_serieActiva!['prefijo']}${(_serieActiva!['siguiente'] as int? ?? 1).toString().padLeft(_serieActiva!['digitos'] as int? ?? 6, '0')} (Próx.)'
                : 'PENDIENTE'),
      ),
      _ResumenRow(
          label: 'Camión',
          value: _camionSeleccionado?.placa ?? _camionTexto.toUpperCase()),
      _ResumenRow(
          label: 'Remolque',
          value: _remolque ? (_remolqueSeleccionado?.placa ?? 'Sí') : 'No'),
      _ResumenRow(
          label: 'Transporte',
          value: _transporteSeleccionado?.razonSocial ?? _transporteTexto),
      _ResumenRow(
          label: 'Conductor',
          value: _conductorSeleccionado?.nombreCompleto ?? _conductorTexto),
      _ResumenRow(
          label: 'Producto',
          value: _productoSeleccionado?.nombre ?? _productoTexto),
      _ResumenRow(
          label: 'Almacén',
          value: _almacenSeleccionado?.nombre ?? _almacenTexto),
      _ResumenRow(label: 'Selección', value: _tipoTercero),
      _ResumenRow(
          label: 'Razón Social',
          value: _terceroSeleccionado?.razonSocial ?? _terceroTexto),
      const Divider(height: 20),
      _ResumenRow(
          label: 'Peso Camión Entrada',
          value: NumberUtils.formatKg(double.tryParse(_pesoEntradaCtrl.text)),
          highlight: true),
      if (ptsRem != null && _remolque)
        _ResumenRow(
            label: 'Peso Remolque', value: NumberUtils.formatKg(ptsRem)),
      _ResumenRow(
          label: 'Peso Total Entrada',
          value: NumberUtils.formatKg(_pesoTotalEntrada),
          highlight: true),
      if (enModoSalida) ...[
        _ResumenRow(
            label: 'Peso Total Salida',
            value: NumberUtils.formatKg(_pesoTotalSalida),
            highlight: true),
        _ResumenRow(
          label: 'Peso Neto Total',
          value: _pesoNetoTotal.abs() == 0
              ? '0,00 kg'
              : '${NumberUtils.formatKg(_pesoNetoTotal.abs())} ${_pesoNetoTotal < 0 ? "(DESPACHO)" : "(INGRESO)"}',
          highlight: true,
        ),
      ],
      _ResumenRow(
          label: 'Peso Neto Declarado',
          value: NumberUtils.formatKg(_pesoNetoDeclarado)),
      if (enModoSalida) ...[
        _ResumenRow(
            label: 'Diferencia',
            value: NumberUtils.formatKg(_pesoDiferencia),
            highlight: _pesoDiferencia != 0),
        _ResumenRow(
            label: '% Desviación',
            value: NumberUtils.formatPercent(_porcentajeDesviacion)),
      ],
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
  final VoidCallback onBuscar;
  final VoidCallback onEntrada;
  final VoidCallback onSalida;
  final VoidCallback onGuardar;
  final VoidCallback onCancelar;
  final VoidCallback onImprimir;
  final VoidCallback onSalir;
  final bool puedeAnular;
  final bool guardando;
  final bool modoSalida;

  const _QuickActionBar({
    required this.onBuscar,
    required this.onEntrada,
    required this.onSalida,
    required this.onGuardar,
    required this.onCancelar,
    required this.onImprimir,
    required this.onSalir,
    required this.puedeAnular,
    this.guardando = false,
    this.modoSalida = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SwsColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _ToolbarButton(
              icon: Icons.search,
              label: context.tr('Buscar'),
              onTap: onBuscar,
              color: SwsColors.accentLight),
          const SizedBox(width: 6),
          _ToolbarButton(
              icon: Icons.input,
              label: context.tr('Entrada'),
              shortcut: 'F2',
              onTap: onEntrada,
              color: modoSalida ? Colors.white70 : SwsColors.accent),
          const SizedBox(width: 6),
          _ToolbarButton(
              icon: Icons.output,
              label: context.tr('Salida'),
              shortcut: 'F6',
              onTap: onSalida,
              color: modoSalida ? SwsColors.success : SwsColors.accentLight),
          const SizedBox(width: 6),
          _ToolbarButton(
            icon: guardando ? Icons.hourglass_top : Icons.save,
            label: guardando ? context.tr('loading') : context.tr('Guardar'),
            shortcut: guardando ? null : 'F4',
            onTap: guardando ? () {} : onGuardar,
            color: modoSalida ? SwsColors.success : SwsColors.accent,
          ),
          const SizedBox(width: 6),
          _ToolbarButton(
              icon: Icons.cancel_outlined,
              label: context.tr('Cancelar'),
              shortcut: 'Esc',
              onTap: onCancelar),
          const SizedBox(width: 6),
          _ToolbarButton(
              icon: Icons.print,
              label: context.tr('Imprimir'),
              shortcut: 'F5',
              onTap: onImprimir),
          const SizedBox(width: 6),
          _ToolbarButton(
            icon: Icons.exit_to_app,
            label: context.tr('Salir'),
            shortcut: 'Esc',
            onTap: onSalir,
          ),
        ],
      ),
    );
  }
}

/// Botón principal del paso activo de captura, dentro de LECTURA DE PESO.
class _CapturarPesoButton extends StatelessWidget {
  final VoidCallback onTap;
  final String etiqueta;
  final bool pendiente;

  const _CapturarPesoButton({
    required this.onTap,
    required this.etiqueta,
    this.pendiente = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: pendiente ? SwsColors.accent : SwsColors.success,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_circle_outline, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                etiqueta,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'F3',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
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
            color: color?.withValues(alpha: 0.15) ??
                Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: btnColor),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: btnColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(shortcut!,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontFamily: 'monospace')),
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

  const _SectionCard(
      {required this.title, required this.icon, required this.children});

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
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: SwsColors.primary)),
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
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: SwsColors.gray500,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ResumenRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _ResumenRow(
      {required this.label, required this.value, this.highlight = false});

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
    final pts =
        pesoSalida != null ? pesoSalida! + (pesoRemolqueSalida ?? 0) : null;
    final pnt = pts != null ? pte - pts : null;
    final pnd = pesoNetoDeclarado ?? 0;
    final pdf = pnt != null ? pnt - pnd : null;
    final pdv = (pdf != null && pnd != 0) ? (pdf / pnd) * 100 : null;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    String pntTxt = '—';
    if (pnt != null) {
      final pntAbs = pnt.abs();
      final tag = pnt < 0
          ? ' (DESPACHO)'
          : (pnt > 0 ? ' (INGRESO)' : ' (SIN MOVIMIENTO)');
      pntTxt = '${NumberUtils.formatKg(pntAbs)}$tag';
    }

    return Card(
      color: oscuro ? SwsColors.darkCard : SwsColors.blue100,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _weightRow(
                context,
                'Balanza Entrada',
                NumberUtils.formatKg(pesoEntrada),
                NumberUtils.formatKg(pesoRemolqueEntrada),
                NumberUtils.formatKg(pte)),
            if (pesoSalida != null) ...[
              _weightRow(
                  context,
                  'Balanza Salida',
                  NumberUtils.formatKg(pesoSalida),
                  NumberUtils.formatKg(pesoRemolqueSalida),
                  NumberUtils.formatKg(pts)),
              const Divider(height: 16),
              _weightRow(context, 'Peso Neto', '', '', pntTxt, bold: true),
              _weightRow(
                  context, 'Peso Declarado', '', '', NumberUtils.formatKg(pnd)),
              _weightRow(
                  context, 'Diferencia', '', '', NumberUtils.formatKg(pdf),
                  bold: pdf != null && pdf != 0),
              _weightRow(context, '% Desviación', '', '',
                  NumberUtils.formatPercent(pdv)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _weightRow(BuildContext context, String label, String camion,
      String remolque, String total,
      {bool bold = false}) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final texto = oscuro ? SwsColors.darkText : SwsColors.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          ),
          if (camion.isNotEmpty)
            Expanded(
                flex: 2,
                child: Text(camion,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11))),
          if (remolque.isNotEmpty)
            Expanded(
                flex: 2,
                child: Text(remolque,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11))),
          Expanded(
            flex: 2,
            child: Text(total,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
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

/// Panel de búsqueda rápida de pesos. Al elegir uno se copia al formulario
/// como borrador editable: nunca se sobrescribe el pesaje original.
class _BusquedaPesajesDialog extends StatefulWidget {
  final ValueChanged<Weighing> onSelected;
  const _BusquedaPesajesDialog({required this.onSelected});

  @override
  State<_BusquedaPesajesDialog> createState() => _BusquedaPesajesDialogState();
}

class _BusquedaPesajesDialogState extends State<_BusquedaPesajesDialog> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<Weighing> _pesos = [];
  bool _loading = true;
  String? _error;
  String _filtro = 'TODOS';

  static const int _maximo = 100;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = di.sl<WeighingRepository>();
      final lista = await repo.listWeighings(limit: _maximo);
      if (!mounted) return;
      setState(() {
        _pesos = lista;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Coincidencia por placa, boleto, conductor, producto, documento o remolque.
  bool _coincide(Weighing w, String q) {
    if (q.isEmpty) return true;
    final campos = <String?>[
      w.idVehiculo,
      w.remolquePlaca,
      w.numeroBoleto,
      w.boleto,
      w.conductorNombre,
      w.idConductor,
      w.productoNombre,
      w.transporteNombre,
      w.terceroNombre,
      w.documento,
      w.guiaSunagro,
    ];
    return campos.whereType<String>().any((c) => c.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = _pesos.where((w) {
      if (!_coincide(w, query)) return false;
      return switch (_filtro) {
        'PENDIENTES' => w.isOpen,
        'CERRADOS' => w.isClosed,
        _ => true,
      };
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.search, color: SwsColors.accent),
          const SizedBox(width: 8),
          Text('weighing_search_weights'.tr(),
              style: const TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'weighing_search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: context.tr('F5'),
                  onPressed: _cargar,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final f in const ['TODOS', 'PENDIENTES', 'CERRADOS']) ...[
                  ChoiceChip(
                    label: Text(switch (f) {
                      'PENDIENTES' => 'weighing_search_open'.tr(),
                      'CERRADOS' => 'weighing_search_closed'.tr(),
                      _ => 'weighing_search_all'.tr(),
                    }),
                    selected: _filtro == f,
                    onSelected: (_) => setState(() => _filtro = f),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                Text('${filtrados.length}',
                    style: const TextStyle(
                        color: SwsColors.gray500, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text('Error: $_error',
                              style: const TextStyle(color: SwsColors.danger)))
                      : filtrados.isEmpty
                          ? Center(
                              child: Text('weighing_search_no_results'.tr(),
                                  style: const TextStyle(
                                      color: SwsColors.gray500)))
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final w = filtrados[index];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: (w.isOpen
                                            ? SwsColors.accent
                                            : SwsColors.success)
                                        .withValues(alpha: 0.15),
                                    child: Icon(
                                      w.isAnulado
                                          ? Icons.block
                                          : (w.isClosed
                                              ? Icons.check_circle
                                              : Icons.directions_car),
                                      color: w.isAnulado
                                          ? SwsColors.danger
                                          : (w.isOpen
                                              ? SwsColors.accent
                                              : SwsColors.success),
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    '${w.idVehiculo ?? "Sin Placa"} — ${w.numeroBoleto ?? w.boleto}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${NumberUtils.formatKg(w.pesoEntradaVehiculo)}   ·   ${w.conductorNombre ?? w.idConductor ?? "N/A"}   ·   ${w.productoNombre ?? w.idProducto ?? "N/A"}\n${app_dates.DateUtils.formatDateTime(w.fechaHoraEntrada.toLocal())}   ·   ${w.estadoBoleto}',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  isThreeLine: true,
                                  trailing: FilledButton.icon(
                                    icon: const Icon(Icons.content_copy,
                                        size: 16),
                                    label: Text('weighing_load_copy'.tr(),
                                        style: const TextStyle(fontSize: 11.5)),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: SwsColors.accent,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                    ),
                                    onPressed: () => widget.onSelected(w),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _BoletoPendienteDialog extends StatefulWidget {
  final ValueChanged<Weighing> onSelected;
  const _BoletoPendienteDialog({required this.onSelected});

  @override
  State<_BoletoPendienteDialog> createState() => _BoletoPendienteDialogState();
}

class _BoletoPendienteDialogState extends State<_BoletoPendienteDialog> {
  final _searchCtrl = TextEditingController();
  List<Weighing> _boletos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarBoletos();
  }

  Future<void> _cargarBoletos() async {
    try {
      final repo = di.sl<WeighingRepository>();
      final list = await repo.listWeighings(estado: 'PENDIENTE');
      if (mounted) {
        setState(() {
          _boletos = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = _boletos.where((b) {
      if (query.isEmpty) return true;
      final num = (b.numeroBoleto ?? b.boleto).toLowerCase();
      final placa = (b.idVehiculo ?? '').toLowerCase();
      final cond = (b.conductorNombre ?? b.idConductor ?? '').toLowerCase();
      final prod = (b.productoNombre ?? b.idProducto ?? '').toLowerCase();
      return num.contains(query) ||
          placa.contains(query) ||
          cond.contains(query) ||
          prod.contains(query);
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.output, color: SwsColors.success),
          const SizedBox(width: 8),
          Text('weighing_pending_for_exit'.tr(),
              style: const TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por Placa, Boleto, Conductor o Producto...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text('Error: $_error',
                              style: const TextStyle(color: SwsColors.danger)))
                      : filtrados.isEmpty
                          ? Center(
                              child: Text('weighing_no_pending'.tr(),
                                  style: const TextStyle(
                                      color: SwsColors.gray500)))
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final b = filtrados[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: SwsColors.accent
                                        .withValues(alpha: 0.15),
                                    child: const Icon(Icons.directions_car,
                                        color: SwsColors.accent, size: 20),
                                  ),
                                  title: Text(
                                    '${b.idVehiculo ?? "Sin Placa"} — ${b.numeroBoleto ?? b.boleto}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5),
                                  ),
                                  subtitle: Text(
                                    'Entrada: ${NumberUtils.formatKg(b.pesoEntradaVehiculo)} | Conductor: ${b.conductorNombre ?? b.idConductor ?? "N/A"}\nProducto: ${b.productoNombre ?? b.idProducto ?? "N/A"}',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  trailing: FilledButton.icon(
                                    icon: const Icon(Icons.output, size: 16),
                                    label: Text('weighing_load_exit'.tr(),
                                        style: const TextStyle(fontSize: 11.5)),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: SwsColors.success,
                                    ),
                                    onPressed: () => widget.onSelected(b),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _BoletoImpresionDialog extends StatefulWidget {
  final String? ultimoBoletoId;
  final String? ultimoNumeroBoleto;
  final void Function(String boletoId, String numeroBoleto, String formato)?
      onImprimir;

  const _BoletoImpresionDialog({
    this.ultimoBoletoId,
    this.ultimoNumeroBoleto,
    this.onImprimir,
  });

  @override
  State<_BoletoImpresionDialog> createState() => _BoletoImpresionDialogState();
}

class _BoletoImpresionDialogState extends State<_BoletoImpresionDialog> {
  final _searchCtrl = TextEditingController();
  List<Weighing> _boletos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarBoletos();
  }

  Future<void> _cargarBoletos() async {
    try {
      final repo = di.sl<WeighingRepository>();
      final list = await repo.listWeighings(limit: 100);
      if (mounted) {
        setState(() {
          _boletos = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  void _abrirPrevisualizacion(Weighing b) {
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (ctx) => TicketPreviewDialog(weighing: b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = _boletos.where((b) {
      if (query.isEmpty) return true;
      final num = (b.numeroBoleto ?? b.boleto).toLowerCase();
      final placa = (b.idVehiculo ?? '').toLowerCase();
      final cond = (b.conductorNombre ?? b.idConductor ?? '').toLowerCase();
      final prod = (b.productoNombre ?? b.idProducto ?? '').toLowerCase();
      return num.contains(query) ||
          placa.contains(query) ||
          cond.contains(query) ||
          prod.contains(query);
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.print, color: SwsColors.accent),
          const SizedBox(width: 8),
          Text('weighing_print_ticket'.tr(),
              style: const TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por Placa, Boleto, Conductor o Producto...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text('Error: $_error',
                              style: const TextStyle(color: SwsColors.danger)))
                      : filtrados.isEmpty
                          ? Center(
                              child: Text('weighing_no_tickets_to_print'.tr(),
                                  style: const TextStyle(
                                      color: SwsColors.gray500)))
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final b = filtrados[index];
                                final isUltimo =
                                    b.boleto == widget.ultimoBoletoId;
                                final estado = b.estadoBoleto;
                                final estadoColor = estado == 'CERRADO'
                                    ? SwsColors.success
                                    : (estado == 'PENDIENTE'
                                        ? SwsColors.warning
                                        : SwsColors.danger);

                                final double displayPeso =
                                    (b.pesoNeto != null && b.pesoNeto != 0)
                                        ? b.pesoNeto!.abs()
                                        : b.pesoEntradaVehiculo;

                                final numVisible = b.numeroBoleto ?? b.boleto;

                                return Container(
                                  color: isUltimo
                                      ? (isDark
                                          ? SwsColors.accent
                                              .withValues(alpha: 0.15)
                                          : SwsColors.accent
                                              .withValues(alpha: 0.08))
                                      : null,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 2),
                                    onTap: () => _abrirPrevisualizacion(b),
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          estadoColor.withValues(alpha: 0.15),
                                      child: Icon(
                                        estado == 'CERRADO'
                                            ? Icons.check_circle
                                            : Icons.hourglass_bottom,
                                        color: estadoColor,
                                        size: 20,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          '$numVisible — Placa: ${b.idVehiculo ?? "Sin Placa"}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: estadoColor.withValues(
                                                alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            estado,
                                            style: TextStyle(
                                                color: estadoColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (isUltimo) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: SwsColors.accent
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'weighing_last'.tr(),
                                              style: const TextStyle(
                                                  color: SwsColors.accent,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Conductor: ${b.conductorNombre ?? b.idConductor ?? "N/A"} | Producto: ${b.productoNombre ?? b.idProducto ?? "N/A"}\nFecha: ${_formatDate(b.createdAt)} | Peso: ${NumberUtils.formatKg(displayPeso)}',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    trailing: FilledButton.icon(
                                      icon: const Icon(Icons.preview, size: 14),
                                      label: Text('weighing_preview'.tr(),
                                          style: const TextStyle(fontSize: 11)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: SwsColors.accent,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          _abrirPrevisualizacion(b),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
