import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'l10n.dart';

class ScanPage extends StatelessWidget{
  const ScanPage({super.key});
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).isArabic ? 'مسح رمز QR' : 'Scan QR')),
      body: MobileScanner(onDetect: (capture){
        final codes = capture.barcodes;
        if (codes.isNotEmpty){
          final raw = codes.first.rawValue;
          if (raw!=null){
            Navigator.pop(context, raw);
          }
        }
      }),
    );
  }
}
