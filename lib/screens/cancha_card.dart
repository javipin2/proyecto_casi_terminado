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
  bool _imageLoaded = false;
  bool _imageError = false;

  // Constantes de estilo centralizadas
  static const _cardBorderRadius = 20.0;
  static const _imageBorderRadius = 16.0;
  static const _chipBorderRadius = 20.0;
  static const _buttonBorderRadius = 16.0;
  static const _cardPadding = 20.0;
  static const _contentSpacing = 12.0;
  
  // Colores unificados
  static const _primaryColor = Color(0xFF2E7D32);
  static const _surfaceColor = Color(0xFFFAFAFA);
  static const _textPrimary = Color(0xFF1A1A1A);
  static const _textSecondary = Color(0xFF6B7280);
  static const _cardShadowColor = Color(0x0A000000);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    
    // Solo para debug, se puede remover en producción
    debugPrint('🏟️ CanchaCard iniciada para: ${widget.cancha.nombre}');
    debugPrint('🖼️ URL de imagen: ${widget.cancha.imagen}');
    debugPrint('🔗 Es URL de red: ${widget.cancha.imagen.startsWith('http')}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool isHovering) {
    setState(() => _isHovering = isHovering);
    isHovering ? _controller.forward() : _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;
    
    return MouseRegion(
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cardBorderRadius),
            boxShadow: [
              BoxShadow(
                color: _isHovering ? _cardShadowColor.withValues(alpha: 0.15) : _cardShadowColor,
                blurRadius: _isHovering ? 20 : 8,
                offset: Offset(0, _isHovering ? 8 : 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: _surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_cardBorderRadius),
              side: BorderSide(
                color: _isHovering ? _primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(_cardBorderRadius),
              splashColor: _primaryColor.withValues(alpha: 0.08),
              highlightColor: _primaryColor.withValues(alpha: 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImageSection(isCompact),
                  _buildContentSection(isCompact),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(bool isCompact) {
    final imageHeight = isCompact ? 160.0 : 200.0;
    
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(_imageBorderRadius)),
      child: SizedBox(
        height: imageHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_imageLoaded && !_imageError) _buildShimmerEffect(),
            _buildHeroImage(),
            if (_imageLoaded) _buildGradientOverlay(),
            Positioned(
              top: 16,
              right: 16,
              child: _buildTipoChip(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection(bool isCompact) {
    return Padding(
      padding: EdgeInsets.all(isCompact ? 16.0 : _cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isCompact),
          const SizedBox(height: _contentSpacing),
          _buildTimeInfo(),
          const SizedBox(height: _contentSpacing),
          _buildDescription(isCompact),
          SizedBox(height: isCompact ? 16 : 20),
          _buildFooter(isCompact),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Text(
      widget.cancha.nombre,
      style: TextStyle(
        fontSize: isCompact ? 20 : 22,
        fontWeight: FontWeight.w700,
        color: _textPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  Widget _buildTimeInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16,
            color: _primaryColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            '7:00 am - 12:00 pm',
            style: TextStyle(
              color: _primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(bool isCompact) {
    return Text(
      widget.cancha.descripcion,
      style: TextStyle(
        fontSize: isCompact ? 14 : 15,
        color: _textSecondary,
        height: 1.5,
        letterSpacing: 0.1,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFooter(bool isCompact) {
    return Row(
      children: [
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _primaryColor.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_buttonBorderRadius),
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: widget.onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 20 : 24,
                vertical: isCompact ? 12 : 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_buttonBorderRadius),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reservar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isCompact ? 14 : 15,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTipoChip() {
    final isTechada = widget.cancha.techada;
    final color = isTechada ? Colors.indigo : Colors.orange;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(_chipBorderRadius),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isTechada ? Icons.home_rounded : Icons.wb_sunny_rounded,
            color: color.withValues(alpha: 0.8),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isTechada ? 'Techada' : 'Al aire',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(_imageBorderRadius)),
        ),
      ),
    );
  }

  Widget _buildHeroImage() {
    return Hero(
      tag: 'cancha_${widget.cancha.id}',
      child: widget.cancha.imagen.startsWith('http')
          ? Image.network(
              widget.cancha.imagen,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  // Solo actualizar estado si no se ha cargado antes
                  if (!_imageLoaded && !_imageError) {
                    debugPrint('✅ Imagen cargada para: ${widget.cancha.nombre}');
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _imageLoaded = true;
                          _imageError = false;
                        });
                      }
                    });
                  }
                  return child;
                } else {
                  // Solo mostrar mensaje de carga la primera vez
                  if (!_imageLoaded && !_imageError) {
                    debugPrint('⏳ Cargando imagen para: ${widget.cancha.nombre}');
                  }
                  return const SizedBox.shrink();
                }
              },
              errorBuilder: (context, error, stackTrace) {
                // Solo actualizar estado si no se ha marcado error antes
                if (!_imageError) {
                  debugPrint('❌ Error cargando imagen para ${widget.cancha.nombre}: $error');
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _imageError = true;
                        _imageLoaded = false;
                      });
                    }
                  });
                }
                return _buildErrorImage('Error al cargar imagen', Icons.cloud_off_rounded);
              },
            )
          : Image.asset(
              widget.cancha.imagen.isNotEmpty 
                  ? widget.cancha.imagen 
                  : 'assets/cancha_demo.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('❌ Error cargando asset para ${widget.cancha.nombre}: $error');
                return _buildErrorImage('Imagen no disponible', Icons.image_not_supported_rounded);
              },
            ),
    );
  }

  Widget _buildErrorImage(String message, IconData icon) {
    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey.shade100, Colors.grey.shade200],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.15),
          ],
          stops: const [0.7, 1.0],
        ),
      ),
    );
  }
}