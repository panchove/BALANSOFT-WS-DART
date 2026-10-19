part of 'catalog_bloc.dart';

abstract class CatalogState extends Equatable {
  const CatalogState();
  @override
  List<Object?> get props => [];
}

class CatalogInitial extends CatalogState {}

class CatalogLoading extends CatalogState {}

class CatalogLoaded extends CatalogState {
  final CatalogData data;
  const CatalogLoaded(this.data);
  @override
  List<Object?> get props => [data];
}

class CatalogError extends CatalogState {
  final String message;
  const CatalogError(this.message);
  @override
  List<Object?> get props => [message];
}