import '../../domain/entities/license.dart';

class LicenseMapper {
  static Map<String, dynamic> toMap(License license) => license.toJson();

  static License fromMap(Map<String, dynamic> map) => License.fromJson(map);
}
