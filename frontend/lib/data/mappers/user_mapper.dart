import '../../domain/entities/user.dart';

class UserMapper {
  static Map<String, dynamic> toMap(User user) => user.toJson();

  static User fromMap(Map<String, dynamic> map) => User.fromJson(map);
}
