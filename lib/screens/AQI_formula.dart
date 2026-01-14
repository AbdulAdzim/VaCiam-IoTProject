import 'package:flutter/material.dart';

class CompositeAQI {
  // Breakpoints for PM2.5 (µg/m³)
  static final List<List<double>> pm25Breakpoints = [
    [0.0, 12.0, 0.0, 50.0],
    [12.1, 35.4, 51.0, 100.0],
    [35.5, 55.4, 101.0, 150.0],
    [55.5, 150.4, 151.0, 200.0],
    [150.5, 250.4, 201.0, 300.0],
    [250.5, 350.4, 301.0, 400.0],
    [350.5, 500.4, 401.0, 500.0],
  ];

  // Breakpoints for NO₂ (ppb)
  static final List<List<double>> noxBreakpoints = [
    [0.0, 53.0, 0.0, 50.0],
    [54.0, 100.0, 51.0, 100.0],
    [101.0, 360.0, 101.0, 150.0],
    [361.0, 649.0, 151.0, 200.0],
    [650.0, 1249.0, 201.0, 300.0],
    [1250.0, 2049.0, 301.0, 500.0],
  ];

  // Generic AQI calculation
  static double _calculateAQI(double concentration, List<List<double>> breakpoints) {
    for (final bp in breakpoints) {
      final cLo = bp[0], cHi = bp[1], iLo = bp[2], iHi = bp[3];
      if (concentration >= cLo && concentration <= cHi) {
        return ((iHi - iLo) / (cHi - cLo)) * (concentration - cLo) + iLo;
      }
    }
    return 500; // cap at 500 if above highest breakpoint
  }

  // Public function to evaluate AQI
  static Map<String, dynamic> evaluate({
    required double pm25,
    required double nox,
  }) {
    final pm25AQI = _calculateAQI(pm25, pm25Breakpoints).round();
    final noxAQI = _calculateAQI(nox, noxBreakpoints).round();

    // Overall AQI = max of pollutants
    final overallAQI = [pm25AQI, noxAQI].reduce((a, b) => a > b ? a : b);

    // Category + color
    String category;
    Color color;
    if (overallAQI <= 50) {
      category = 'Good';
      color = Colors.green;
    } else if (overallAQI <= 100) {
      category = 'Moderate';
      color = const Color.fromARGB(255, 213, 197, 52);
    } else if (overallAQI <= 150) {
      category = 'Unhealthy for Sensitive Groups';
      color = Colors.orange;
    } else if (overallAQI <= 200) {
      category = 'Unhealthy';
      color = Colors.red;
    } else if (overallAQI <= 300) {
      category = 'Very Unhealthy';
      color = Colors.purple;
    } else {
      category = 'Hazardous';
      color = Colors.brown;
    }

    return {
      'aqi': overallAQI,
      'category': category,
      'color': color,
      'details': {
        'pm25AQI': pm25AQI,
        'noxAQI': noxAQI,
      }
    };
  }
}