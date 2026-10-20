// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 (Usabilidad/Accesibilidad)
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n/translations.dart';
import '../theme/app_theme.dart';

class PhotoCaptured {
  final Uint8List bytes;
  final String nombre;

  const PhotoCaptured({required this.bytes, required this.nombre});
}

/// Campo de captura de fotos (camara o galería) reutilizable.
class PhotoPickerField extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<PhotoCaptured> fotos;
  final ValueChanged<List<PhotoCaptured>> onChanged;
  final int maxFotos;

  /// Imagen ya guardada en el servidor (URL **absoluta**). Se muestra mientras
  /// el usuario no capture una nueva; al capturar una, la reemplaza en pantalla.
  /// Sin esto, un logo guardado "desaparece" al reabrir el formulario.
  final String? imagenUrl;

  const PhotoPickerField({
    super.key,
    this.label = 'Fotos',
    this.icon = Icons.photo_camera_outlined,
    this.fotos = const [],
    required this.onChanged,
    this.maxFotos = 4,
    this.imagenUrl,
  });

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  final _picker = ImagePicker();

  Future<void> _tomarFoto() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (xfile != null) await _agregarXFile(xfile);
    } catch (e) {
      _errorSnack('No se pudo tomar la foto: $e');
    }
  }

  Future<void> _elegirGaleria() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (xfile != null) await _agregarXFile(xfile);
    } catch (e) {
      _errorSnack('No se pudo cargar la imagen: $e');
    }
  }

  Future<void> _agregarXFile(XFile xfile) async {
    final bytes = await xfile.readAsBytes();
    if (widget.fotos.length >= widget.maxFotos) {
      _errorSnack('Máximo ${widget.maxFotos} fotos');
      return;
    }
    final nombre = xfile.name.isEmpty
        ? 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg'
        : xfile.name;
    widget.onChanged([...widget.fotos, PhotoCaptured(bytes: bytes, nombre: nombre)]);
  }

  void _errorSnack(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: SwsColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fotos = widget.fotos;
    final url = widget.imagenUrl?.trim();
    final hayRemota = fotos.isEmpty && url != null && url.isNotEmpty;
    final total = fotos.length + (hayRemota ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 18, color: SwsColors.gray500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Text(
              '$total/${widget.maxFotos}',
              style: const TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hayRemota)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: SwsColors.gray200,
                        child: const Icon(Icons.broken_image_outlined,
                            color: SwsColors.gray500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (fotos.isNotEmpty)
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < fotos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            fotos[i].bytes,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () {
                              final nueva = [...fotos]..removeAt(i);
                              widget.onChanged(nueva);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (hayRemota || fotos.isNotEmpty) const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: fotos.length >= widget.maxFotos ? null : _tomarFoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text('take_photo'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SwsColors.primary,
                  side: BorderSide(color: SwsColors.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: fotos.length >= widget.maxFotos ? null : _elegirGaleria,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text('upload'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SwsColors.primary,
                  side: BorderSide(color: SwsColors.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}