import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/repositories/i_catalog_repository.dart';
import 'package:balansoft_ws/domain/repositories/i_kardex_repository.dart';
import 'package:balansoft_ws/domain/repositories/i_license_repository.dart';
import 'package:balansoft_ws/domain/repositories/i_weighing_repository.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/providers/bloc/license/license_bloc.dart';
import 'package:balansoft_ws/presentation/providers/bloc/sync/sync_bloc.dart';
import 'package:balansoft_ws/presentation/providers/bloc/weighing/weighing_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await di.sl.reset();
  });

  tearDown(() async {
    await di.sl.reset();
  });

  test('di.init() registra y resuelve IAuthRepository y AuthBloc sin fallos', () async {
    await di.init();

    expect(di.sl.isRegistered<IAuthRepository>(), isTrue);
    expect(di.sl.isRegistered<IWeighingRepository>(), isTrue);
    expect(di.sl.isRegistered<ILicenseRepository>(), isTrue);
    expect(di.sl.isRegistered<ICatalogRepository>(), isTrue);
    expect(di.sl.isRegistered<IKardexRepository>(), isTrue);

    // Resuelve AuthBloc sin lanzar Bad state
    final authBloc = di.sl<AuthBloc>();
    expect(authBloc, isNotNull);

    final weighingBloc = di.sl<WeighingBloc>();
    expect(weighingBloc, isNotNull);

    final licenseBloc = di.sl<LicenseBloc>();
    expect(licenseBloc, isNotNull);

    final syncBloc = di.sl<SyncBloc>();
    expect(syncBloc, isNotNull);
  });
}

