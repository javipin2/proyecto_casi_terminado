import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapaSeleccionUbicacion extends StatefulWidget {
  final double? latitudInicial;
  final double? longitudInicial;
  final Function(double latitud, double longitud) onUbicacionSeleccionada;

  const MapaSeleccionUbicacion({
    super.key,
    this.latitudInicial,
    this.longitudInicial,
    required this.onUbicacionSeleccionada,
  });

  @override
  State<MapaSeleccionUbicacion> createState() => _MapaSeleccionUbicacionState();
}

class _MapaSeleccionUbicacionState extends State<MapaSeleccionUbicacion> {
  GoogleMapController? _mapController;
  LatLng? _ubicacionSeleccionada;
  bool _isLoadingUbicacion = false;
  Position? _posicionActual;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  Timer? _debounceTimer;
  Timer? _searchDebounceTimer;
  bool _isDisposed = false;
  MapType _mapType = MapType.normal;

  // API Key de Google Maps
  static const String _apiKey = 'AIzaSyBlQw337BN4KaSWPky3cH2rmgDTvstACpo';

  // Ubicación por defecto (Valledupar, Colombia)
  static const LatLng _ubicacionDefault = LatLng(10.4631, -73.2532);

  @override
  void initState() {
    super.initState();
    // Inicializar con la ubicación proporcionada o la ubicación por defecto
    if (widget.latitudInicial != null && widget.longitudInicial != null) {
      _ubicacionSeleccionada = LatLng(widget.latitudInicial!, widget.longitudInicial!);
    } else {
      _ubicacionSeleccionada = _ubicacionDefault;
    }

    // Para móvil, inicializar permisos temprano
    if (!kIsWeb) {
      _inicializarPermisos();
    }
  }

  Future<void> _inicializarPermisos() async {
    try {
      await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('Error verificando permisos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // ⭐ CAMBIADO
      children: [
        Text(
          'Ubicación de la Sede',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF212121),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _ubicacionSeleccionada != null
                  ? const Color(0xFF2196F3).withOpacity(0.3)
                  : Colors.red.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                _buildMap(),
                _buildSearchBar(),
                _buildMapControls(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_ubicacionSeleccionada != null) _buildLocationInfo(),
      ],
    );
  }

  Widget _buildMap() {
    try {
      return GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _ubicacionSeleccionada ?? _ubicacionDefault,
          zoom: 15,
        ),
        onMapCreated: (GoogleMapController controller) {
          if (!_isDisposed) {
            _mapController = controller;
            debugPrint('✅ Mapa creado correctamente');
          }
        },
        onTap: (LatLng position) {
          if (!_isDisposed) {
            setState(() {
              _ubicacionSeleccionada = position;
            });

            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 300), () {
              if (mounted && !_isDisposed) {
                widget.onUbicacionSeleccionada(position.latitude, position.longitude);
              }
            });
          }
        },
        markers: _ubicacionSeleccionada != null
            ? {
          Marker(
            markerId: const MarkerId('sede_ubicacion'),
            position: _ubicacionSeleccionada!,
            draggable: true,
            onDragEnd: (LatLng newPosition) {
              if (!_isDisposed) {
                setState(() {
                  _ubicacionSeleccionada = newPosition;
                });

                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                  if (mounted && !_isDisposed) {
                    widget.onUbicacionSeleccionada(newPosition.latitude, newPosition.longitude);
                  }
                });
              }
            },
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        }
            : {},
        myLocationButtonEnabled: false,
        myLocationEnabled: true,
        zoomControlsEnabled: !kIsWeb,
        mapToolbarEnabled: false,
        mapType: _mapType,
        compassEnabled: true,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
          ),
        },
      );
    } catch (e) {
      debugPrint('❌ Error creando mapa: $e');
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Error al cargar el mapa',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.red[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Por favor, verifica tu conexión',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildSearchBar() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // ⭐ AGREGADO
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar ubicación...',
                hintStyle: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2196F3)),
                suffixIcon: _isSearching
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _showSearchResults = false;
                      _searchResults = [];
                    });
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: GoogleFonts.montserrat(fontSize: 14),
              onChanged: (value) {
                _searchDebounceTimer?.cancel();
                if (value.length >= 3) {
                  _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
                    if (!_isDisposed && mounted) {
                      _buscarUbicaciones(value);
                    }
                  });
                } else {
                  setState(() {
                    _showSearchResults = false;
                    _searchResults = [];
                  });
                }
              },
              onSubmitted: (value) {
                _searchDebounceTimer?.cancel();
                if (value.length >= 3 && !_isDisposed && mounted) {
                  _buscarUbicaciones(value);
                }
              },
            ),
          ),
          if (_showSearchResults && _searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on, color: Color(0xFF2196F3), size: 20),
                    title: Text(
                      result['description'] ?? '',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      _seleccionarUbicacionDesdeBusqueda(result);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      bottom: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<MapType>(
              icon: const Icon(Icons.layers, color: Color(0xFF2196F3), size: 20),
              tooltip: 'Tipo de mapa',
              onSelected: (MapType type) {
                setState(() {
                  _mapType = type;
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: MapType.normal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // ⭐ AGREGADO
                    children: [
                      const Icon(Icons.map, size: 18),
                      const SizedBox(width: 8),
                      Text('Normal', style: GoogleFonts.montserrat(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: MapType.satellite,
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // ⭐ AGREGADO
                    children: [
                      const Icon(Icons.satellite, size: 18),
                      const SizedBox(width: 8),
                      Text('Satelital', style: GoogleFonts.montserrat(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: MapType.terrain,
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // ⭐ AGREGADO
                    children: [
                      const Icon(Icons.terrain, size: 18),
                      const SizedBox(width: 8),
                      Text('Terreno', style: GoogleFonts.montserrat(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: MapType.hybrid,
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // ⭐ AGREGADO
                    children: [
                      const Icon(Icons.layers, size: 18),
                      const SizedBox(width: 8),
                      Text('Híbrido', style: GoogleFonts.montserrat(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            mini: true,
            backgroundColor: Colors.white,
            onPressed: _irAUbicacionActual,
            tooltip: 'Mi ubicación',
            child: _isLoadingUbicacion
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.my_location, color: Color(0xFF2196F3)),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ubicación seleccionada: ${_ubicacionSeleccionada!.latitude.toStringAsFixed(6)}, ${_ubicacionSeleccionada!.longitude.toStringAsFixed(6)}',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _irAUbicacionActual() async {
    if (_isDisposed || !mounted) return;

    setState(() {
      _isLoadingUbicacion = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Por favor, activa los servicios de ubicación',
                style: GoogleFonts.montserrat(),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isLoadingUbicacion = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Se necesitan permisos de ubicación',
                  style: GoogleFonts.montserrat(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            _isLoadingUbicacion = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Los permisos de ubicación están deshabilitados permanentemente. Actívalos en la configuración.',
                style: GoogleFonts.montserrat(),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() {
          _isLoadingUbicacion = false;
        });
        return;
      }

      _posicionActual = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      final nuevaUbicacion = LatLng(
        _posicionActual!.latitude,
        _posicionActual!.longitude,
      );

      if (!_isDisposed && mounted) {
        setState(() {
          _ubicacionSeleccionada = nuevaUbicacion;
        });

        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(nuevaUbicacion, 16),
          );
        }

        widget.onUbicacionSeleccionada(nuevaUbicacion.latitude, nuevaUbicacion.longitude);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ubicación actual obtenida',
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al obtener la ubicación',
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoadingUbicacion = false;
        });
      }
    }
  }

  Future<void> _buscarUbicaciones(String query) async {
    if (query.length < 3 || _isDisposed) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
            '?input=${Uri.encodeComponent(query)}'
            '&key=$_apiKey'
            '&language=es'
            '&components=country:co',
      );

      debugPrint('🔍 Buscando: $query');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      debugPrint('📡 Status Code: ${response.statusCode}');

      if (response.statusCode == 200 && !_isDisposed) {
        final data = json.decode(response.body);

        debugPrint('✅ Status API: ${data['status']}');

        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = List<Map<String, dynamic>>.from(data['predictions']);

          debugPrint('📍 Resultados encontrados: ${predictions.length}');

          if (!_isDisposed && mounted) {
            setState(() {
              _searchResults = predictions;
              _showSearchResults = true;
            });
          }
        } else {
          debugPrint('⚠️ No hay resultados: ${data['status']}');
          if (data['error_message'] != null) {
            debugPrint('❌ Error: ${data['error_message']}');
          }

          if (!_isDisposed && mounted) {
            setState(() {
              _searchResults = [];
              _showSearchResults = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error en búsqueda: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
        });
      }
    } finally {
      if (!_isDisposed && mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _seleccionarUbicacionDesdeBusqueda(Map<String, dynamic> place) async {
    if (_isDisposed) return;

    try {
      setState(() {
        _isSearching = true;
        _showSearchResults = false;
      });

      final placeId = place['place_id'] as String;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
            '?place_id=$placeId'
            '&key=$_apiKey'
            '&language=es'
            '&fields=geometry,formatted_address',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && !_isDisposed) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'];
          final geometry = result['geometry'];
          final location = geometry['location'];

          final lat = location['lat'] as double;
          final lng = location['lng'] as double;

          final nuevaUbicacion = LatLng(lat, lng);

          if (!_isDisposed && mounted) {
            setState(() {
              _ubicacionSeleccionada = nuevaUbicacion;
              _searchController.text = result['formatted_address'] ?? place['description'] ?? '';
            });

            if (_mapController != null) {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(nuevaUbicacion, 16),
              );
            }

            widget.onUbicacionSeleccionada(lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint('Error obteniendo detalles del lugar: $e');
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al obtener la ubicación',
              style: GoogleFonts.montserrat(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (!_isDisposed && mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    _debounceTimer?.cancel();
    _searchDebounceTimer?.cancel();

    Future.microtask(() {
      try {
        _mapController?.dispose();
      } catch (e) {
        debugPrint('Error disposing map controller: $e');
      }
      _mapController = null;
    });

    _searchController.dispose();
    super.dispose();
  }
}