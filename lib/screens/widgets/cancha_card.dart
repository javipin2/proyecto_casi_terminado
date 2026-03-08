import 'package:flutter/material.dart';
import '../../models/cancha.dart';

// Mismos colores que tarjetas de sede/lugar
const _cardOverlayBg = Color(0xE6181818);
const _textPrimary = Color(0xFF1F2937);
const _textSecondary = Color(0xFF6B7280);
const _tagBg = Color(0xFFF3F4F6);
const _accentTeal = Color(0xFF2DD4BF);

class CanchaCard extends StatelessWidget {
  final Cancha cancha;
  final VoidCallback onTap;

  const CanchaCard({
    super.key,
    required this.cancha,
    required this.onTap,
  });

  static const _imageHeight = 180.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.black.withOpacity(0.06),
          highlightColor: Colors.black.withOpacity(0.04),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: _imageHeight,
                      width: double.infinity,
                      child: _buildImage(),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _buildTipoOverlay(),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: _buildPrecioOverlay(),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cancha.nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (cancha.descripcion.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          cancha.descripcion,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: _textSecondary,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _tagBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'CANCHA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _tagBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              cancha.techada ? 'TECHADA' : 'AIRE',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (cancha.imagen.startsWith('http')) {
      return Image.network(
        cancha.imagen,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                color: _accentTeal,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: _textSecondary,
                size: 40,
              ),
            ),
          );
        },
      );
    }
    return Image.asset(
      cancha.imagen.isNotEmpty ? cancha.imagen : 'assets/demo.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: _textSecondary,
              size: 40,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTipoOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _cardOverlayBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cancha.techada ? Icons.roofing_rounded : Icons.wb_sunny_rounded,
            color: _accentTeal,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            cancha.techada ? 'Techada' : 'Aire',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrecioOverlay() {
    final precioStr = cancha.precio > 0
        ? 'Desde \$${cancha.precio.toStringAsFixed(0)}'
        : 'Consultar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _cardOverlayBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.payments_rounded, color: _accentTeal, size: 16),
          const SizedBox(width: 4),
          Text(
            precioStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
