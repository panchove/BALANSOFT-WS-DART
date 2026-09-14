import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/forms/autocomplete_creatable.dart';
import '../../../core/widgets/forms/create_item_dialog.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/services/scale_api_client.dart';
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
    CrearCampoSpec(
      key: 'placa',
      label: 'Placa',
      icon: Icons.tag_outlined,
      requerido: true,
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'color',
      label: 'Color',
      icon: Icons.palette_outlined,
    ),
    CrearCampoSpec(
      key: 'tara_habitual',
      label: 'Tara habitual (kg)',
      icon: Icons.fitness_center,
      tipo: CrearCampoTipo.numero,
    ),
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
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'tipo_remolque',
      label: 'Tipo de remolque',
      icon: Icons.category_outlined,
    ),
    CrearCampoSpec(
      key: 'tara_habitual',
      label: 'Tara habitual (kg)',
      icon: Icons.fitness_center,
      tipo: CrearCampoTipo.numero,
    ),
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
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'codigo',
      label: 'Código',
      icon: Icons.numbers_outlined,
    ),
    CrearCampoSpec(
      key: 'identificacion_fiscal',
      label: 'RIF / Identificación fiscal',
      icon: Icons.badge_outlined,
    ),
    CrearCampoSpec(
      key: 'contacto',
      label: 'Contacto',
      icon: Icons.person_outline,
    ),
    CrearCampoSpec(
      key: 'telefono',
      label: 'Teléfono',
      icon: Icons.phone_outlined,
    ),
  ],
);

const _specProducto = CreatableSpec<Product>(
  path: ApiConstants.productos,
  titulo: 'Nuevo Producto',
  icon: Icons.inventory,
  parse: Product.fromJson,
  campos: [
    CrearCampoSpec(
      key: 'nombre',
      label: 'Nombre',
      icon: Icons.badge_outlined,
      requerido: true,
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'codigo',
      label: 'Código',
      icon: Icons.numbers_outlined,
    ),
    CrearCampoSpec(
      key: 'densidad_estandar',
      label: 'Densidad estándar',
      icon: Icons.speed_outlined,
      tipo: CrearCampoTipo.numero,
    ),
    CrearCampoSpec(
      key: 'unidad_medida',
      label: 'Unidad de medida',
      icon: Icons.straighten_outlined,
      tipo: CrearCampoTipo.dropdown,
      opciones: ['TON', 'KG', 'LBS', 'UN'],
    ),
    CrearCampoSpec(
      key: 'es_kardex',
      label: 'Generar movimiento de kardex',
      icon: Icons.book_outlined,
      tipo: CrearCampoTipo.booleano,
    ),
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
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'codigo',
      label: 'Código',
      icon: Icons.numbers_outlined,
    ),
    CrearCampoSpec(
      key: 'ubicacion',
      label: 'Ubicación',
      icon: Icons.place_outlined,
    ),
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
      precargarTexto: true,
    ),
    CrearCampoSpec(
      key: 'codigo',
      label: 'Código',
      icon: Icons.numbers_outlined,
    ),
    CrearCampoSpec(
      key: 'marca',
      label: 'Marca',
      icon: Icons.local_offer_outlined,
    ),
    CrearCampoSpec(
      key: 'modelo',
      label: 'Modelo',
      icon: Icons.model_training,
    ),
  ],
);

class WeighingFormScreen extends StatelessWidget {
  const WeighingFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CatalogBloc>(
      create: (_) => di.sl<CatalogBloc>()..add(const FetchCatalogsEvent()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Nuevo Pesaje')),
        body: const _WeighingFormBody(),
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

  final _pesoEntradaCtrl = TextEditingController();
  final _pesoRemolqueCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();
  final _fleteCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  bool _remolque = false;
  String _tipoTercero = 'CLIENTE';
  bool _esPesoManual = false;
  bool _puedePesoManual = false;
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

  void _registrarNuevo(String tipo, Object item) {
    setState(() {
      (_nuevos[tipo] ??= []).add(item);
    });
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
        await api.uploadImage(
            boleto, entrada.foto.bytes, entrada.foto.nombre, tipo: entrada.tipo);
      }
    } catch (_) {
      // Si falla la subida, no bloqueamos el flujo del pesaje.
    }
  }

  List<T> _unidos<T>(String tipo, List<T> base) =>
      [...base, ...(_nuevos[tipo] ?? const []).cast<T>()];

  bool _pareceCedula(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^(V|E|J|G|P)?-?\d{3,}$').hasMatch(t);
  }

  @override
  void initState() {
    super.initState();
    _cargarPermisos();
  }

  Future<void> _cargarPermisos() async {
    final user = await di.sl<LocalStorage>().getCachedUser();
    if (!mounted) return;
    setState(() {
      _puedePesoManual =
          user?.rol == 'ADMIN' || user?.rol == 'SUPERVISOR';
    });
  }

  @override
  void dispose() {
    _pesoEntradaCtrl.dispose();
    _pesoRemolqueCtrl.dispose();
    _documentoCtrl.dispose();
    _fleteCtrl.dispose();
    _costoFleteCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  void _onRemolqueSeleccionado(Trailer? trailer) {
    setState(() {
      _remolqueSeleccionado = trailer;
      if (trailer != null && _pesoRemolqueCtrl.text.trim().isEmpty) {
        _pesoRemolqueCtrl.text =
            trailer.taraHabitual?.toStringAsFixed(2) ?? '';
      }
    });
  }

  void _onSave() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final now = DateTime.now();
    final placa =
        _camionSeleccionado?.placa ?? _camionTexto.toUpperCase();

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
      pesoEntradaRemolque: _remolque
          ? double.tryParse(_pesoRemolqueCtrl.text)
          : null,
      documento: _documentoCtrl.text.trim().isNotEmpty
          ? _documentoCtrl.text.trim()
          : null,
      flete: _fleteCtrl.text.trim().isNotEmpty ? _fleteCtrl.text.trim() : null,
      costoFlete: double.tryParse(_costoFleteCtrl.text),
      observaciones: _observacionesCtrl.text.trim().isNotEmpty
          ? _observacionesCtrl.text.trim()
          : null,
      createdAt: now,
      updatedAt: now,
    );

    final adicionales = <String, dynamic>{
      'remolque_placa': _remolque
          ? (_remolqueSeleccionado?.placa ?? _remolqueTexto)
          : null,
      'transporte_nombre':
          _transporteSeleccionado?.razonSocial ?? _transporteTexto,
      'conductor_nombre': _conductorTexto,
      'producto_nombre': _productoSeleccionado?.nombre ?? _productoTexto,
      'almacen_nombre': _almacenSeleccionado?.nombre ?? _almacenTexto,
      'balanza_nombre':
          _balanzaSeleccionada?.descripcion ?? _balanzaTexto,
      'tercero_nombre': _terceroSeleccionado?.razonSocial ?? _terceroTexto,
      'es_peso_manual': _esPesoManual,
    };

    context
        .read<WeighingBloc>()
        .add(CreateWeighingEvent(weighing, adicionales: adicionales));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WeighingBloc, WeighingState>(
      listener: (context, state) {
        if (state is WeighingCreated) {
          final boleto = state.weighing.boleto;
          _subirFotos(boleto);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pesaje creado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else if (state is WeighingError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
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

  Widget _buildForm(BuildContext context, CatalogData data) {
    final trailers = data.trailersActivos;
    final terceros = data.tercerosPorTipo(_tipoTercero);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScaleMonitorWidget(
              client: _scaleClient,
              label: 'Báscula de entrada',
              balanzaId: _balanzaSeleccionada?.id,
              balanzaDescripcion: _balanzaSeleccionada?.descripcion,
              initialWeight:
                  double.tryParse(_pesoEntradaCtrl.text) ?? 0,
              onPesoLeido: (peso) {
                _pesoEntradaCtrl.text = peso.toStringAsFixed(2);
                if (_puedePesoManual) setState(() => _esPesoManual = true);
              },
            ),
            SizedBox(height: 12,),
            AutocompleteCreatable<Camion>(
              items: _unidos('camion', data.camiones),
              label: (v) => v.placa,
              search: (v) => '${v.placa} ${v.color ?? ''}',
              required: true,
              fieldName: 'Placa',
              icon: Icons.directions_car,
              hint: 'Escriba la placa o seleccione una existente',
              fieldKey: const Key('placa_field'),
              onSelected: (v) =>
                  setState(() => _camionSeleccionado = v),
              onTextChanged: (text) {
                _camionSeleccionado = null;
                _camionTexto = text.trim();
              },
              onCreated: (v) => _registrarNuevo('camion', v),
              crear: _puedePesoManual ? _specCamion : null,
            ),
            const SizedBox(height: 12),
            PhotoPickerField(
              label: 'Fotos del camión',
              icon: Icons.directions_car_outlined,
              fotos: _fotosCamion,
              onChanged: (f) => setState(() => _fotosCamion = f),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Tiene remolque'),
              value: _remolque,
              activeThumbColor: Theme.of(context).colorScheme.primary,
              onChanged: (v) => setState(() {
                _remolque = v;
                if (!v) {
                  _remolqueSeleccionado = null;
                  _pesoRemolqueCtrl.clear();
                  _fotosRemolque = [];
                }
              }),
            ),
            if (_remolque) ...[
              const SizedBox(height: 12),
              AutocompleteCreatable<Trailer>(
                items: _unidos('remolque', trailers),
                label: (t) => t.placa,
                search: (t) => '${t.placa} ${t.tipo ?? ''}',
                required: false,
                fieldName: 'Remolque',
                icon: Icons.local_shipping_outlined,
                hint: 'Escriba la placa o seleccione una existente',
                onSelected: _onRemolqueSeleccionado,
                onTextChanged: (text) {
                  _remolqueSeleccionado = null;
                  _remolqueTexto = text.trim();
                },
                onCreated: (t) => _registrarNuevo('remolque', t),
                crear: _puedePesoManual ? _specRemolque : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pesoRemolqueCtrl,
                decoration: const InputDecoration(
                  labelText: 'Peso Remolque Entrada (kg)',
                  hintText: 'Se sugiere la tara del remolque',
                  prefixIcon: Icon(Icons.fitness_center),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final num = double.tryParse(v);
                  if (num == null || num < 0) return 'Peso remolque debe ser positivo';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              PhotoPickerField(
                label: 'Fotos del remolque',
                icon: Icons.local_shipping_outlined,
                fotos: _fotosRemolque,
                onChanged: (f) => setState(() => _fotosRemolque = f),
              ),
            ],
            const SizedBox(height: 12),
            AutocompleteCreatable<Transport>(
              items: _unidos('transporte', data.transports),
              label: (t) => t.etiqueta,
              search: (t) =>
                  '${t.razonSocial} ${t.codigo ?? ''} ${t.contacto ?? ''}',
              required: false,
              fieldName: 'Transporte',
              icon: Icons.fire_truck_outlined,
              hint: 'Escriba la razón social o seleccione una existente',
              onSelected: (t) =>
                  setState(() => _transporteSeleccionado = t),
              onTextChanged: (text) {
                _transporteSeleccionado = null;
                _transporteTexto = text.trim();
              },
              onCreated: (t) => _registrarNuevo('transporte', t),
              crear: _puedePesoManual ? _specTransporte : null,
            ),
            const SizedBox(height: 12),
            AutocompleteCreatable<Driver>(
              items: _unidos('conductor', data.drivers),
              label: (d) => '${d.nombreCompleto} (${d.cedulaDni})',
              search: (d) => '${d.nombreCompleto} ${d.cedulaDni}',
              required: false,
              fieldName: 'Conductor',
              icon: Icons.person,
              hint: 'Escriba cédula o nombre',
              onSelected: (d) =>
                  setState(() => _conductorSeleccionado = d),
              onTextChanged: (text) {
                _conductorSeleccionado = null;
                _conductorTexto = text.trim();
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
                              : _conductorTexto,
                        ),
                        CrearCampoSpec(
                          key: 'cedula_dni',
                          label: 'Cédula / DNI',
                          icon: Icons.badge_outlined,
                          requerido: true,
                          initial: _pareceCedula(_conductorTexto)
                              ? _conductorTexto
                              : null,
                        ),
                        const CrearCampoSpec(
                          key: 'telefono',
                          label: 'Teléfono',
                          icon: Icons.phone_outlined,
                        ),
                        const CrearCampoSpec(
                          key: 'licencia_conducir',
                          label: 'Licencia de conducir',
                          icon: Icons.credit_card_outlined,
                        ),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            AutocompleteCreatable<Product>(
              items: _unidos('producto', data.products),
              label: (p) => p.etiqueta,
              search: (p) => '${p.nombre} ${p.codigo ?? ''}',
              required: false,
              fieldName: 'Producto',
              icon: Icons.inventory,
              hint: 'Escriba el nombre del producto o seleccione uno',
              onSelected: (p) => setState(() => _productoSeleccionado = p),
              onTextChanged: (text) {
                _productoSeleccionado = null;
                _productoTexto = text.trim();
              },
              onCreated: (p) => _registrarNuevo('producto', p),
              crear: _puedePesoManual ? _specProducto : null,
            ),
            const SizedBox(height: 12),
            AutocompleteCreatable<Warehouse>(
              items: _unidos('almacen', data.warehouses),
              label: (w) => w.etiqueta,
              search: (w) => '${w.nombre} ${w.codigo ?? ''}',
              required: false,
              fieldName: 'Almacén',
              icon: Icons.warehouse,
              hint: 'Escriba el nombre o seleccione uno',
              onSelected: (w) => setState(() => _almacenSeleccionado = w),
              onTextChanged: (text) {
                _almacenSeleccionado = null;
                _almacenTexto = text.trim();
              },
              onCreated: (w) => _registrarNuevo('almacen', w),
              crear: _puedePesoManual ? _specAlmacen : null,
            ),
            const SizedBox(height: 12),
            AutocompleteCreatable<Scale>(
              items: _unidos('balanza', data.scales),
              label: (s) => s.etiqueta,
              search: (s) => '${s.descripcion} ${s.codigo ?? ''} ${s.marca ?? ''}',
              required: false,
              fieldName: 'Balanza',
              icon: Icons.scale,
              hint: 'Escriba la descripción o seleccione una balanza',
              onSelected: (s) => setState(() => _balanzaSeleccionada = s),
              onTextChanged: (text) {
                _balanzaSeleccionada = null;
                _balanzaTexto = text.trim();
              },
              onCreated: (s) => _registrarNuevo('balanza', s),
              crear: _puedePesoManual ? _specBalanza : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tipoTercero,
              decoration: const InputDecoration(
                labelText: 'Tipo de Tercero',
                prefixIcon: Icon(Icons.people_outline),
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
            const SizedBox(height: 12),
            AutocompleteCreatable<ThirdParty>(
              items: _unidos('tercero', terceros),
              label: (t) => t.etiqueta,
              search: (t) =>
                  '${t.razonSocial} ${t.codigo ?? ''} ${t.identificacionFiscal ?? ''} ${t.tipo}',
              required: false,
              fieldName: 'Tercero',
              icon: Icons.business,
              hint: 'Escriba la razón social o seleccione uno',
              onSelected: (t) => setState(() => _terceroSeleccionado = t),
              onTextChanged: (text) {
                _terceroSeleccionado = null;
                _terceroTexto = text.trim();
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
                          precargarTexto: true,
                        ),
                        CrearCampoSpec(
                          key: 'tipo',
                          label: 'Tipo',
                          icon: Icons.category_outlined,
                          tipo: CrearCampoTipo.dropdown,
                          opciones: ['CLIENTE', 'PROVEEDOR', 'AMBOS'],
                          requerido: true,
                          initial: _tipoTercero,
                        ),
                        const CrearCampoSpec(
                          key: 'codigo',
                          label: 'Código',
                          icon: Icons.numbers_outlined,
                        ),
                        const CrearCampoSpec(
                          key: 'identificacion_fiscal',
                          label: 'RIF / Identificación fiscal',
                          icon: Icons.badge_outlined,
                        ),
                        const CrearCampoSpec(
                          key: 'telefono',
                          label: 'Teléfono',
                          icon: Icons.phone_outlined,
                        ),
                        const CrearCampoSpec(
                          key: 'direccion',
                          label: 'Dirección',
                          icon: Icons.place_outlined,
                          tipo: CrearCampoTipo.multilinea,
                        ),
                        const CrearCampoSpec(
                          key: 'email',
                          label: 'Email',
                          icon: Icons.email_outlined,
                          tipo: CrearCampoTipo.email,
                        ),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('peso_entrada_field'),
              controller: _pesoEntradaCtrl,
              decoration: const InputDecoration(
                labelText: 'Peso Entrada Vehículo (kg) *',
                prefixIcon: Icon(Icons.monitor_weight),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Peso'),
            ),
            if (_puedePesoManual) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Registro manual del peso'),
                subtitle: const Text('Solo disponible para Supervisor/Admin'),
                value: _esPesoManual,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setState(() => _esPesoManual = v),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentoCtrl,
              decoration: const InputDecoration(
                labelText: 'Documento / Referencia',
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fleteCtrl,
              decoration: const InputDecoration(
                labelText: 'Flete (ref. / descripción)',
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _costoFleteCtrl,
              decoration: const InputDecoration(
                labelText: 'Costo del Flete',
                prefixIcon: Icon(Icons.attach_money),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesCtrl,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            BlocBuilder<WeighingBloc, WeighingState>(
              builder: (context, state) {
                final isLoading = state is WeighingLoading;
                return ElevatedButton(
                  key: const Key('guardar_entrada_button'),
                  onPressed: isLoading ? null : _onSave,
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registrar Pesaje'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}