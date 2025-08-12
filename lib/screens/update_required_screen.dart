// lib/screens/update_required_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/version_provider.dart';
import '../models/app_version.dart';

class UpdateRequiredScreen extends StatefulWidget {
  final bool canDismiss;
  
  const UpdateRequiredScreen({
    super.key,
    this.canDismiss = false,
  });

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();

    // Configurar status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Configurar animaciones
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    HapticFeedback.mediumImpact();

    final versionProvider = Provider.of<VersionProvider>(context, listen: false);
    
    try {
      // Solicitar permisos si es necesario
      await versionProvider.requestDownloadPermissions();
      
      // Abrir URL de actualización
      final success = await versionProvider.openUpdateUrl();
      
      if (!success) {
        _showErrorDialog('No se pudo abrir el enlace de descarga');
      }
    } catch (e) {
      _showErrorDialog('Error al intentar actualizar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => widget.canDismiss,
      child: Scaffold(
        body: Consumer<VersionProvider>(
          builder: (context, versionProvider, child) {
            final versionConfig = versionProvider.versionConfig;
            final isMaintenanceMode = versionProvider.isInMaintenance;
            
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isMaintenanceMode
                      ? [
                          const Color(0xFF6B46C1),
                          const Color(0xFF8B5CF6),
                          const Color(0xFFA855F7),
                        ]
                      : [
                          const Color(0xFF2E7D60),
                          const Color(0xFF4CAF50),
                          const Color(0xFF66BB6A),
                        ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    children: [
                      // Header con logo
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: _buildHeader(isMaintenanceMode),
                        ),
                      ),

                      const Spacer(),

                      // Contenido principal
                      SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: _buildMainContent(versionConfig, isMaintenanceMode),
                        ),
                      ),

                      const Spacer(),

                      // Botones de acción
                      SlideTransition(
                        position: _slideAnimation,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: _buildActionButtons(versionProvider, isMaintenanceMode),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMaintenanceMode) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: isMaintenanceMode
              ? const Icon(
                  Icons.build_circle,
                  size: 60,
                  color: Colors.white,
                )
              : Image.asset(
                  'assets/img1.png',
                  width: 80,
                  height: 80,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.system_update,
                      size: 60,
                      color: Colors.white,
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        Text(
          isMaintenanceMode ? 'Mantenimiento' : 'Actualización Requerida',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMainContent(AppVersion? versionConfig, bool isMaintenanceMode) {
    if (isMaintenanceMode) {
      return _buildMaintenanceContent(versionConfig);
    } else {
      return _buildUpdateContent(versionConfig);
    }
  }

  Widget _buildMaintenanceContent(AppVersion? versionConfig) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.settings,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            versionConfig?.maintenanceMessage ?? 
            'La aplicación está temporalmente en mantenimiento.',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Estaremos de vuelta pronto.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateContent(AppVersion? versionConfig) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.system_update,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            versionConfig?.updateMessage ?? 
            'Es necesario actualizar la aplicación para continuar.',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          
          // Información de versión
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Versión actual',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    Provider.of<VersionProvider>(context).currentAppVersion,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Icon(
                Icons.arrow_forward,
                color: Colors.white70,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Nueva versión',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    versionConfig?.currentVersion ?? '1.0.0',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Nuevas características
          if (versionConfig?.newFeatures.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✨ Novedades:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...versionConfig!.newFeatures.take(3).map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(VersionProvider versionProvider, bool isMaintenanceMode) {
    if (isMaintenanceMode) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.lightImpact();
                await versionProvider.retryUpdateCheck();
              },
              icon: versionProvider.isCheckingForUpdates
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.purple.shade800,
                        ),
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(
                versionProvider.isCheckingForUpdates 
                    ? 'Verificando...' 
                    : 'Reintentar',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.purple.shade800,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Botón principal de actualización
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _isUpdating ? null : _handleUpdate,
            icon: _isUpdating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF2E7D60),
                      ),
                    ),
                  )
                : const Icon(Icons.download),
            label: Text(
              _isUpdating ? 'Abriendo enlace...' : 'Descargar Actualización',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2E7D60),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(27),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Información adicional
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                versionProvider.versionConfig?.isPlayStoreAvailable == true
                    ? Icons.play_circle_outline
                    : Icons.download_outlined,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                versionProvider.versionConfig?.isPlayStoreAvailable == true
                    ? 'Se abrirá Google Play Store'
                    : 'Se descargará el archivo APK',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Información de seguridad
        const Text(
          '🔒 Descarga segura y verificada',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white60,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}