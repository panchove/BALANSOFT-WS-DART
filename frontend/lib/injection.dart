import 'package:get_it/get_it.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'presentation/providers/bloc/auth/auth_bloc.dart';
import 'presentation/providers/bloc/weighing/weighing_bloc.dart';
import 'presentation/providers/bloc/license/license_bloc.dart';
import 'presentation/providers/bloc/sync/sync_bloc.dart';
import 'presentation/providers/bloc/catalog/catalog_bloc.dart';
import 'presentation/providers/bloc/catalog_crud/catalog_crud_cubit.dart';
import 'data/datasources/remote/api_client.dart';
import 'data/datasources/local/local_storage.dart';
import 'data/datasources/local/database_helper.dart';
import 'core/security/secure_storage_service.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/weighing_repository.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/accesos_repository.dart';
import 'data/repositories/kardex_repository.dart';
import 'data/repositories/license_repository.dart';
import 'domain/usecases/auth_usecases.dart';
import 'domain/usecases/weighing_usecases.dart';
import 'domain/usecases/catalog_usecases.dart';
import 'domain/usecases/kardex_usecases.dart';
import 'domain/usecases/license_usecases.dart';
import 'presentation/providers/bloc/kardex/kardex_bloc.dart';
import 'data/services/scale_api_client.dart';
import 'data/services/scale_tcp_client.dart';
import 'data/datasources/remote/scale_api_datasource.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  final connectivity = Connectivity();

  // Datasources
  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<LocalStorage>(() => LocalStorage());
  sl.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());
  sl.registerLazySingleton<SecureStorageService>(() => SecureStorageService());

  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository(
        apiClient: sl(),
        localStorage: sl(),
        secureStorage: sl(),
      ));
  sl<ApiClient>().onUnauthorized(() => sl<AuthRepository>().refreshAccessToken());
  sl.registerLazySingleton<WeighingRepository>(() => WeighingRepository(
        apiClient: sl(),
        dbHelper: sl(),
        connectivity: connectivity,
      ));
  sl.registerLazySingleton<LicenseRepository>(() => LicenseRepository(
        apiClient: sl(),
        localStorage: sl(),
        connectivity: connectivity,
      ));
  sl.registerLazySingleton<CatalogRepository>(() => CatalogRepository(
        apiClient: sl(),
        dbHelper: sl(),
        connectivity: connectivity,
      ));
  sl.registerLazySingleton<KardexRepository>(
      () => KardexRepository(apiClient: sl<ApiClient>()));
  sl.registerLazySingleton<AccesosRepository>(() => AccesosRepository(
        apiClient: sl(),
        localStorage: sl(),
      ));

  // Use cases
  sl.registerLazySingleton<LoginUseCase>(
      () => LoginUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<RegisterUseCase>(
      () => RegisterUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<LogoutUseCase>(
      () => LogoutUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<GetCachedUserUseCase>(
      () => GetCachedUserUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<RestoreSessionUseCase>(
      () => RestoreSessionUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<ForgotPasswordUseCase>(
      () => ForgotPasswordUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<ResetPasswordUseCase>(
      () => ResetPasswordUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<CreateWeighingUseCase>(
      () => CreateWeighingUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<CloseWeighingUseCase>(
      () => CloseWeighingUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<AnularWeighingUseCase>(
      () => AnularWeighingUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<GetWeighingUseCase>(
      () => GetWeighingUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<ListWeighingsUseCase>(
      () => ListWeighingsUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<SyncWeighingsUseCase>(
      () => SyncWeighingsUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<GetPendingWeighingsCountUseCase>(
      () => GetPendingWeighingsCountUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<GetFailedWeighingsUseCase>(
      () => GetFailedWeighingsUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<GetFailedWeighingsCountUseCase>(
      () => GetFailedWeighingsCountUseCase(sl<WeighingRepository>()));
  sl.registerLazySingleton<ValidateLicenseUseCase>(
      () => ValidateLicenseUseCase(sl<LicenseRepository>()));
  sl.registerLazySingleton<GetCachedLicenseUseCase>(
      () => GetCachedLicenseUseCase(sl<LicenseRepository>()));
  sl.registerLazySingleton<ClearLicenseCacheUseCase>(
      () => ClearLicenseCacheUseCase(sl<LicenseRepository>()));
  sl.registerLazySingleton<SyncCatalogsUseCase>(
      () => SyncCatalogsUseCase(sl<CatalogRepository>()));
  sl.registerLazySingleton<GetCachedCatalogsUseCase>(
      () => GetCachedCatalogsUseCase(sl<CatalogRepository>()));
  sl.registerLazySingleton<KardexDetalleUseCase>(
      () => KardexDetalleUseCase(sl<KardexRepository>()));
  sl.registerLazySingleton<ExportKardexExcelUseCase>(
      () => ExportKardexExcelUseCase(sl<KardexRepository>()));
  sl.registerLazySingleton<ExportKardexPdfUseCase>(
      () => ExportKardexPdfUseCase(sl<KardexRepository>()));

  // Blocs
  sl.registerFactory<AuthBloc>(() => AuthBloc(
        loginUseCase: sl(),
        registerUseCase: sl(),
        logoutUseCase: sl(),
        getCachedUserUseCase: sl(),
        restoreSessionUseCase: sl(),
        forgotPasswordUseCase: sl(),
        resetPasswordUseCase: sl(),
      ));
  sl.registerFactory<WeighingBloc>(() => WeighingBloc(
        createUseCase: sl(),
        closeUseCase: sl(),
        anularUseCase: sl(),
        getUseCase: sl(),
        listUseCase: sl(),
        syncUseCase: sl(),
        failedCountUseCase: sl(),
      ));
  sl.registerFactory<LicenseBloc>(() => LicenseBloc(
        validateUseCase: sl(),
        getCachedUseCase: sl(),
        clearCacheUseCase: sl(),
      ));
  sl.registerFactory<SyncBloc>(() => SyncBloc(
        syncUseCase: sl(),
        pendingCountUseCase: sl(),
        failedCountUseCase: sl(),
        healthCheck: () => sl<ApiClient>().health(),
      ));
  sl.registerFactory<CatalogBloc>(() => CatalogBloc(
        syncUseCase: sl(),
        cachedUseCase: sl(),
      ));
  sl.registerFactory<KardexBloc>(
      () => KardexBloc(detalleUseCase: sl<KardexDetalleUseCase>()));
  sl.registerFactory<CatalogCrudCubit>(
      () => CatalogCrudCubit(sl<ApiClient>()));
  sl.registerLazySingleton<ScaleTcpClient>(() => ScaleTcpClient());
  sl.registerLazySingleton<ScaleApiClient>(
      () => ScaleApiClient(datasource: ScaleApiDatasource(sl<ApiClient>())));
  // Respaldo TCP: config de báscula/dispositivo guardada en Ajustes.
  final scaleCfg = await sl<LocalStorage>().getScaleConfig();
  sl<ScaleApiClient>().configurarFallbackTcp(scaleCfg.host, scaleCfg.port);

  // Migración one-shot: mover tokens de SharedPreferences al almacén seguro.
  await sl<SecureStorageService>().migrateFromSharedPreferences();
}
