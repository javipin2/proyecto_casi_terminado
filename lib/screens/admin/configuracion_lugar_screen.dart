import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reserva_canchas/models/config_lugar.dart';
import 'package:reserva_canchas/models/lugar.dart';
import 'package:reserva_canchas/providers/lugar_provider.dart';
import 'package:reserva_canchas/services/config_lugar_service.dart';
import 'package:reserva_canchas/services/lugar_helper.dart';

/// Pantalla de configuración del lugar: horarios de actividad (L-D), WhatsApp y cuentas.
/// Para admin usa el lugar del usuario; para superadmin permite elegir lugar.
class ConfigLugarScreen extends StatefulWidget {
  const ConfigLugarScreen({super.key});

  @override
  State<ConfigLugarScreen> createState() => _ConfigLugarScreenState();
}

class _ConfigLugarScreenState extends State<ConfigLugarScreen> {
  String? _lugarId;
  String? _rol;
  bool _loadingLugar = true;
  bool _loadingConfig = true;
  bool _saving = false;
  ConfigLugar _config = ConfigLugar();
  final _formKey = GlobalKey<FormState>();
  final _whatsappController = TextEditingController();
  final _cuentasController = TextEditingController();
  final List<String> _nombresDias = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final rol = await LugarHelper.getUserRole();
    final lugarId = await LugarHelper.getLugarId();
    if (!mounted) return;
    setState(() {
      _rol = rol;
      _lugarId = lugarId;
      _loadingLugar = false;
    });
    if (rol == 'superadmin') {
      context.read<LugarProvider>().fetchTodosLosLugares();
    }
    if (lugarId != null && lugarId.isNotEmpty) {
      await _cargarConfig(lugarId);
    } else {
      setState(() => _loadingConfig = false);
    }
  }

  Future<void> _cargarConfig(String lugarId) async {
    setState(() => _loadingConfig = true);
    final config = await ConfigLugarService.getConfig(lugarId);
    if (!mounted) return;
    setState(() {
      _config = config;
      _whatsappController.text = config.whatsappReservas;
      _cuentasController.text = config.textoCuentasReservas;
      _loadingConfig = false;
    });
  }

  @override
  void dispose() {
    _whatsappController.dispose();
    _cuentasController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_lugarId == null || _lugarId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un lugar para guardar')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final config = ConfigLugar(
      horariosActividad: Map.from(_config.horariosActividad),
      whatsappReservas: _whatsappController.text.trim(),
      textoCuentasReservas: _cuentasController.text.trim(),
    );

    setState(() => _saving = true);
    try {
      await ConfigLugarService.setConfig(_lugarId!, config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _actualizarHorarioDia(int weekday, HorarioDia value) {
    setState(() {
      _config = _config.copyWith(
        horariosActividad: Map.from(_config.horariosActividad)..[weekday] = value,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingLugar) {
      return const Center(child: CircularProgressIndicator());
    }

    final isSuper = _rol == 'superadmin';
    final lugares = context.watch<LugarProvider>().lugares;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configuración del lugar',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Horarios de actividad, WhatsApp y cuentas para reservas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 24),

            if (isSuper) ...[
              DropdownButtonFormField<String>(
                value: _lugarId,
                decoration: const InputDecoration(
                  labelText: 'Lugar',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('-- Selecciona un lugar --')),
                  ...lugares.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nombre))),
                ],
                onChanged: (id) async {
                  setState(() => _lugarId = id);
                  if (id != null && id.isNotEmpty) await _cargarConfig(id);
                },
              ),
              const SizedBox(height: 20),
            ],

            if (_lugarId == null && !isSuper)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tienes un lugar asignado. Contacta al administrador.'),
              )
            else if (_lugarId != null && _lugarId!.isNotEmpty) ...[
              if (_loadingConfig)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Horarios de actividad (entrada de clientes)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Si el día está cerrado o fuera del rango, en la app se mostrará "Cerrado" y no se podrá reservar.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(7, (i) {
                          final weekday = i + 1;
                          final h = _config.horarioDia(weekday);
                          return _FilaHorarioDia(
                            nombreDia: _nombresDias[i],
                            cerrado: h.cerrado,
                            inicio: h.inicio,
                            fin: h.fin,
                            onChanged: (cerrado, inicio, fin) => _actualizarHorarioDia(
                              weekday,
                              HorarioDia(cerrado: cerrado, inicio: inicio, fin: fin),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WhatsApp y cuentas para reservas',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Número y texto de cuentas que se envían en el mensaje de confirmación al cliente.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _whatsappController,
                          decoration: const InputDecoration(
                            labelText: 'Número de WhatsApp (ej: +573001234567)',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _cuentasController,
                          decoration: const InputDecoration(
                            labelText: 'Texto de cuentas para transferencia',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaHorarioDia extends StatefulWidget {
  final String nombreDia;
  final bool cerrado;
  final String inicio;
  final String fin;
  final void Function(bool cerrado, String inicio, String fin) onChanged;

  const _FilaHorarioDia({
    required this.nombreDia,
    required this.cerrado,
    required this.inicio,
    required this.fin,
    required this.onChanged,
  });

  @override
  State<_FilaHorarioDia> createState() => _FilaHorarioDiaState();
}

class _FilaHorarioDiaState extends State<_FilaHorarioDia> {
  late bool _cerrado;
  late TextEditingController _inicioController;
  late TextEditingController _finController;
  static final RegExp _hhmm = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');

  @override
  void initState() {
    super.initState();
    _cerrado = widget.cerrado;
    _inicioController = TextEditingController(text: widget.inicio);
    _finController = TextEditingController(text: widget.fin);
  }

  @override
  void didUpdateWidget(_FilaHorarioDia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inicio != widget.inicio) _inicioController.text = widget.inicio;
    if (oldWidget.fin != widget.fin) _finController.text = widget.fin;
    if (oldWidget.cerrado != widget.cerrado) _cerrado = widget.cerrado;
  }

  @override
  void dispose() {
    _inicioController.dispose();
    _finController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_cerrado, _inicioController.text.trim(), _finController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(widget.nombreDia, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Checkbox(
            value: _cerrado,
            onChanged: (v) {
              setState(() {
                _cerrado = v ?? false;
                _notify();
              });
            },
          ),
          const Text('Cerrado', style: TextStyle(fontSize: 12)),
          if (!_cerrado) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 80,
              child: TextFormField(
                controller: _inicioController,
                decoration: const InputDecoration(
                  labelText: 'Inicio',
                  hintText: '06:00',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _notify(),
                validator: (v) {
                  if (_cerrado) return null;
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Requerido';
                  if (!_hhmm.hasMatch(t)) return 'HH:mm';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextFormField(
                controller: _finController,
                decoration: const InputDecoration(
                  labelText: 'Fin',
                  hintText: '22:00',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _notify(),
                validator: (v) {
                  if (_cerrado) return null;
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Requerido';
                  if (!_hhmm.hasMatch(t)) return 'HH:mm';
                  return null;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
