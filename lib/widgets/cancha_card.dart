import 'package:flutter/material.dart';
import '../models/cancha.dart';
import 'package:shimmer/shimmer.dart';

class CanchaCard extends StatefulWidget {
  final Cancha cancha;
  final VoidCallback onTap;

  const CanchaCard({
    super.key,
    required this.cancha,
    required this.onTap,
  });

  @override
  State<CanchaCard> createState() => _CanchaCardState();
}

class _CanchaCardState extends State<CanchaCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool isHovering) {
    setState(() {
      _isHovering = isHovering;
    });
    if (isHovering) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          elevation: _isHovering ? 5 : 1,
          shadowColor: _isHovering ? Colors.black26 : Colors.black12,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _isHovering ? Colors.grey.shade300 : Colors.transparent,
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.green.withOpacity(0.1),
            highlightColor: Colors.green.withOpacity(0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: _buildImage(),
                ),
                _buildCardContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.cancha.nombre,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF303030),
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildTipoChip(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '7:00 am - 12:00 pm',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.cancha.descripcion,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2), // Espacio donde estaba el precio
            ],
          ),
        ),
        ElevatedButton(
          onPressed: widget.onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade50,
            foregroundColor: Colors.grey.shade800,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Reservar',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: Colors.grey.shade800,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTipoChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            widget.cancha.techada ? Colors.blue.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: widget.cancha.techada
              ? Colors.blue.shade200
              : Colors.amber.shade200,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.cancha.techada
                ? Icons.home_outlined
                : Icons.wb_sunny_outlined,
            color: widget.cancha.techada
                ? Colors.blue.shade700
                : Colors.amber.shade700,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            widget.cancha.techada ? 'Techada' : 'Al aire',
            style: TextStyle(
              color: widget.cancha.techada
                  ? Colors.blue.shade700
                  : Colors.amber.shade700,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Construye la imagen de la cancha desde Firestore
  Widget _buildImage() {
    return Container(
      height: 180,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildShimmerEffect(),
          _buildHeroImage(),
          _buildGradientOverlay(),
        ],
      ),
    );
  }

  /// Efecto de carga tipo shimmer mientras se obtiene la imagen
  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: 180,
        width: double.infinity,
        color: Colors.white,
      ),
    );
  }

  /// Muestra la imagen desde Firestore o una imagen local si falta la URL
  Widget _buildHeroImage() {
    return Hero(
      tag: 'cancha_${widget.cancha.id}',
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: widget.cancha.imagen.startsWith('http')
                ? NetworkImage(widget.cancha.imagen)
                : const AssetImage('assets/cancha_demo.png') as ImageProvider,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  /// Agrega un gradiente sutil a la imagen
  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.1),
            Colors.black.withOpacity(0.4),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
    );
  }
}
