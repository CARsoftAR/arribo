import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // For SystemNavigator.pop

class TermsScreen extends StatefulWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;

  // Legal text constant
  static const String _legalText = '''TÉRMINOS Y CONDICIONES DE alarMap

1. NATURALEZA DEL SERVICIO (DISCLAIMER)
alarMap es una herramienta de asistencia basada en geolocalización. El Usuario reconoce que factores externos fuera del control del Desarrollador (precisión del GPS, señal de red, gestión de energía de Android/Doze Mode y nivel de batería) pueden afectar el funcionamiento.

2. LIMITACIÓN DE RESPONSABILIDAD
El Desarrollador NO SERÁ RESPONSABLE por:

Daños directos o indirectos, pérdida de tiempo, pérdida de oportunidades laborales o gastos de transporte derivados de que una alarma no se active o falle.

El uso de esta app en situaciones críticas es bajo total y exclusivo riesgo del Usuario.

3. PRIVACIDAD Y UBICACIÓN
Para funcionar, la app requiere acceso a la ubicación en segundo plano. Estos datos se procesan localmente para el monitoreo de la distancia y no son comercializados con terceros.

4. ACEPTACIÓN DEL RIESGO
Al tocar 'ACEPTAR', usted declara entender que alarMap es una herramienta complementaria y no un sistema de seguridad infalible.''';

  Future<void> _acceptTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terms_accepted', true);
    // Navigate to home (MapScreen) – assumed route is '/' or you can use Navigator pushReplacement with MapScreen.
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _decline() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _legalText,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (value) {
                      setState(() {
                        _accepted = value ?? false;
                      });
                    },
                    activeColor: Colors.white,
                    checkColor: Colors.black,
                  ),
                  const Expanded(
                    child: Text(
                      'He leído y acepto el Descargo de Responsabilidad y las Políticas de Privacidad',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: _accepted ? _acceptTerms : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('ACEPTAR Y ENTRAR'),
                  ),
                  TextButton(
                    onPressed: _decline,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    child: const Text('NO ACEPTO'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
