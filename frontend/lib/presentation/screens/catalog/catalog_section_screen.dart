import 'package:flutter/material.dart';

import '../../../core/constants/catalog_resources.dart';
import '../../../core/theme/app_theme.dart';
import 'catalog_crud_screen.dart';

class CatalogSectionScreen extends StatelessWidget {
  final CatalogSection seccion;

  const CatalogSectionScreen({super.key, required this.seccion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(seccion.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final recurso in seccion.recursos)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(recurso.icono, size: 20),
                ),
                title: Text(recurso.plural),
                subtitle: Text(
                  'Gestionar ${recurso.plural.toLowerCase()}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CatalogCrudScreen(recurso: recurso),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}