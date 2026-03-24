import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

/// Comandos ESC/POS para impressoras térmicas
class EscPosCommands {
  // Comandos básicos
  static const List<int> reset = [0x1B, 0x40]; // ESC @
  static const List<int> lineFeed = [0x0A]; // LF
  static const List<int> cut = [0x1D, 0x56, 0x00]; // GS V 0 (corte total)
  static const List<int> partialCut = [0x1D, 0x56, 0x01]; // GS V 1 (corte parcial)
  
  // Alinhamento
  static const List<int> alignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> alignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> alignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  
  // Estilo de texto
  static const List<int> boldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> boldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> doubleHeightOn = [0x1B, 0x21, 0x10]; // ESC ! 16
  static const List<int> normalSize = [0x1B, 0x21, 0x00]; // ESC ! 0
  
  // Caracteres especiais - linha horizontal
  static String horizontalLine(int width) => '-' * width;
}

/// Serviço para gerenciar impressão via Bluetooth em impressoras térmicas ESC/POS
class BluetoothPrinterService {
  static BluetoothPrinterService? _instance;
  static BluetoothPrinterService get instance {
    _instance ??= BluetoothPrinterService._();
    return _instance!;
  }

  BluetoothPrinterService._();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  bool _isConnected = false;
  bool _isScanning = false;
  final List<ScanResult> _scanResults = [];

  // Largura padrão para impressora 80mm (48 caracteres) ou 58mm (32 caracteres)
  int _printerWidth = 32;

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<ScanResult> get scanResults => _scanResults;

  /// Solicita permissões necessárias para Bluetooth no Android
  Future<bool> requestPermissions() async {
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }

    // Verifica se as permissões críticas foram concedidas
    // Nota: Em algumas versões do Android (Android 11 e anteriores), bluetoothScan/Connect 
    // podem ser considerados permanentes ou gerenciados via BLUETOOTH_ADMIN.
    // O mais importante é garantir que o app tenha acesso.
    return await Permission.bluetoothConnect.isGranted || await Permission.bluetooth.isGranted;
  }

  /// Verifica se o Bluetooth está ligado
  Future<bool> isBluetoothOn() async {
    if (kIsWeb) return false;
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('Erro ao verificar Bluetooth: $e');
      return false;
    }
  }

  /// Retorna a lista de dispositivos Bluetooth pareados e conectados pelo sistema
  Future<List<BluetoothDevice>> getBondedDevices() async {
    if (kIsWeb) return [];
    try {
      // Garante permissões antes de buscar
      await requestPermissions();

      // Obtém dispositivos pareados explicitamente
      final bondedDevices = await FlutterBluePlus.bondedDevices;
      
      // Obtém dispositivos que o sistema Android já considera conectados
      final systemDevices = await FlutterBluePlus.connectedSystemDevices;
      
      // Une as listas removendo duplicatas
      final allDevices = [...bondedDevices, ...systemDevices];
      final Map<String, BluetoothDevice> uniqueDevices = {};
      
      for (var device in allDevices) {
        // Filtra por nomes que pareçam impressoras se necessário, ou mostra todos
        uniqueDevices[device.remoteId.str] = device;
      }
      
      return uniqueDevices.values.toList();
    } catch (e) {
      debugPrint('Erro ao obter dispositivos: $e');
      return [];
    }
  }

  /// Inicia scan de novos dispositivos
  Future<void> startScan() async {
    if (_isScanning) return;
    
    try {
      _scanResults.clear();
      _isScanning = true;
      
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );
      
      FlutterBluePlus.scanResults.listen((results) {
        _scanResults.clear();
        _scanResults.addAll(results);
      });
    } catch (e) {
      debugPrint('Erro ao iniciar scan: $e');
      _isScanning = false;
    }
  }

  /// Para o scan
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }

  /// Conecta à impressora Bluetooth
  Future<bool> connect(BluetoothDevice device) async {
    if (kIsWeb) return false;
    try {
      // Desconecta dispositivo anterior se houver
      await disconnect();

      // Configura listener para desconexão inesperada
      final subscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _writeCharacteristic = null;
          _connectedDevice = null;
          debugPrint('Dispositivo desconectado inesperadamente');
        }
      });

      // Conecta ao dispositivo
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Solicita MTU maior para envio de dados mais rápido (Android)
      try {
        await device.requestMtu(244);
        debugPrint('MTU solicitado: 244');
      } catch (e) {
        debugPrint('Erro ao solicitar MTU: $e');
      }

      // Aguarda um pouco para estabilizar conexão
      await Future.delayed(const Duration(milliseconds: 500));

      // Descobre serviços
      List<BluetoothService> services = await device.discoverServices();
      
      // Procura pela característica de escrita
      // Tenta primeiro o serviço de porta serial comum (0xFF00 ou 0x18F0 ou 0x4953)
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeCharacteristic = char;
            _isConnected = true;
            debugPrint('Conectado à impressora: ${device.platformName}');
            debugPrint('Serviço: ${service.uuid}, Caract: ${char.uuid}');
            return true;
          }
        }
      }

      debugPrint('Característica de escrita não encontrada');
      await disconnect();
      subscription.cancel();
      return false;
    } catch (e) {
      debugPrint('Erro ao conectar: $e');
      await disconnect();
      return false;
    }
  }

  /// Desconecta da impressora
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
    } catch (e) {
      debugPrint('Erro ao desconectar: $e');
    } finally {
      _connectedDevice = null;
      _writeCharacteristic = null;
      _isConnected = false;
    }
  }

  /// Converte texto para bytes Latin-1 (compatível com impressoras térmicas)
  List<int> _textToBytes(String text) {
    // Substitui caracteres acentuados por equivalentes simples para compatibilidade
    final Map<String, String> replacements = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
      'Á': 'A', 'À': 'A', 'Ã': 'A', 'Â': 'A', 'Ä': 'A',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
      'Ó': 'O', 'Ò': 'O', 'Õ': 'O', 'Ô': 'O', 'Ö': 'O',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'Ç': 'C', 'Ñ': 'N',
      '\u00A0': ' ', // Non-breaking space
    };
    
    String normalized = text;
    replacements.forEach((key, value) {
      normalized = normalized.replaceAll(key, value);
    });
    
    return latin1.encode(normalized);
  }

  /// Imprime texto formatado para impressora térmica
  Future<bool> printReceipt({
    required String title,
    String? subtitle,
    required List<Map<String, String>> items,
    String? total,
    String? footer,
  }) async {
    if (!_isConnected || _writeCharacteristic == null) {
      debugPrint('Impressora não conectada');
      return false;
    }

    try {
      List<int> bytes = [];

      // Reset
      bytes.addAll(EscPosCommands.reset);

      // Título centralizado e grande
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(EscPosCommands.doubleHeightOn);
      bytes.addAll(_textToBytes(title));
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.normalSize);

      // Subtítulo se houver
      if (subtitle != null && subtitle.isNotEmpty) {
        bytes.addAll(EscPosCommands.boldOff);
        for (var line in subtitle.split('\n')) {
          bytes.addAll(_textToBytes(line));
          bytes.addAll(EscPosCommands.lineFeed);
        }
      }

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Alinha à esquerda para itens
      bytes.addAll(EscPosCommands.alignLeft);
      bytes.addAll(EscPosCommands.boldOn);

      // Itens
      for (var item in items) {
        final name = item['name'] ?? '';
        final qty = item['qty'] ?? '';
        final price = item['price'] ?? '';

        if (qty.isNotEmpty && price.isNotEmpty) {
          // Formato: QTD PRODUTO          VALOR
          final qtyStr = qty.padRight(3);
          final priceStr = price.padLeft(10);
          final nameMaxLen = _printerWidth - qtyStr.length - priceStr.length;
          final nameStr = name.length > nameMaxLen 
              ? name.substring(0, nameMaxLen) 
              : name.padRight(nameMaxLen);
          
          bytes.addAll(_textToBytes('$qtyStr$nameStr$priceStr'));
          bytes.addAll(EscPosCommands.lineFeed);
        } else {
          bytes.addAll(_textToBytes(name));
          bytes.addAll(EscPosCommands.lineFeed);
        }
      }

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Total
      if (total != null && total.isNotEmpty) {
        bytes.addAll(EscPosCommands.alignRight);
        bytes.addAll(EscPosCommands.doubleHeightOn);
        bytes.addAll(_textToBytes('TOTAL: $total'));
        bytes.addAll(EscPosCommands.lineFeed);
        bytes.addAll(EscPosCommands.normalSize);
      }

      // Rodapé (sem linha extra)
      if (footer != null && footer.isNotEmpty) {
        bytes.addAll(EscPosCommands.alignCenter);
        bytes.addAll(EscPosCommands.boldOff);
        bytes.addAll(_textToBytes(footer));
        bytes.addAll(EscPosCommands.lineFeed);
      }

      // Avanço mínimo antes do corte
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.partialCut);

      // Envia dados para a impressora
      await _sendData(bytes);

      return true;
    } catch (e) {
      debugPrint('Erro ao imprimir: $e');
      return false;
    }
  }

  /// Imprime lista de despesas formatada
  Future<bool> printExpenses({
    required List<Map<String, String>> items,
    required String total,
    required String period,
  }) async {
    if (!_isConnected || _writeCharacteristic == null) {
      debugPrint('Impressora não conectada');
      return false;
    }

    try {
      List<int> bytes = [];

      // Reset
      bytes.addAll(EscPosCommands.reset);

      // Cabeçalho
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(EscPosCommands.doubleHeightOn);
      bytes.addAll(_textToBytes('RELATORIO DE DESPESAS'));
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.normalSize);
      bytes.addAll(_textToBytes('Periodo: $period'));
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(_textToBytes('Gerado: ${DateFormat('dd/MM HH:mm').format(DateTime.now())}'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Alinha à esquerda para itens
      bytes.addAll(EscPosCommands.alignLeft);

      // Itens
      for (var item in items) {
        final dia = item['dia'] ?? '';
        final beneficiary = item['beneficiary'] ?? '';
        final value = item['value'] ?? '';

        bytes.addAll(EscPosCommands.boldOn);
        bytes.addAll(_textToBytes('D:$dia - $beneficiary'));
        bytes.addAll(EscPosCommands.lineFeed);
        
        bytes.addAll(EscPosCommands.boldOff);
        bytes.addAll(EscPosCommands.alignRight);
        bytes.addAll(_textToBytes(value));
        bytes.addAll(EscPosCommands.lineFeed);
        bytes.addAll(EscPosCommands.alignLeft);
      }

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Total
      bytes.addAll(EscPosCommands.alignRight);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(EscPosCommands.doubleHeightOn);
      bytes.addAll(_textToBytes('TOTAL: $total'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Rodapé
      bytes.addAll(EscPosCommands.normalSize);
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOff);
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(_textToBytes('*** FIM DO RELATORIO ***'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Avanço mínimo antes do corte
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.partialCut);

      await _sendData(bytes);
      return true;
    } catch (e) {
      debugPrint('Erro ao imprimir lista de despesas: $e');
      return false;
    }
  }

  /// Imprime lista de clientes formatada
  Future<bool> printClientes({
    required List<Map<String, String>> items,
  }) async {
    if (!_isConnected || _writeCharacteristic == null) {
      debugPrint('Impressora não conectada');
      return false;
    }

    try {
      List<int> bytes = [];

      // Reset
      bytes.addAll(EscPosCommands.reset);

      // Cabeçalho
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(EscPosCommands.doubleHeightOn);
      bytes.addAll(_textToBytes('LISTA DE CLIENTES'));
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.normalSize);
      bytes.addAll(_textToBytes('Gerado em: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Alinha à esquerda para itens
      bytes.addAll(EscPosCommands.alignLeft);

      // Itens
      for (var item in items) {
        final name = item['name'] ?? '';
        final info = item['info'] ?? ''; // Pode ser telefone ou cidade

        bytes.addAll(EscPosCommands.boldOn);
        bytes.addAll(_textToBytes(name));
        bytes.addAll(EscPosCommands.lineFeed);
        
        if (info.isNotEmpty) {
          bytes.addAll(EscPosCommands.boldOff);
          bytes.addAll(_textToBytes('  $info'));
          bytes.addAll(EscPosCommands.lineFeed);
        }
        
        bytes.addAll(EscPosCommands.lineFeed); // Espaço entre clientes
      }

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Rodapé
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOff);
      bytes.addAll(_textToBytes('FIM DA LISTA'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Avanço mínimo antes do corte
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.partialCut);

      await _sendData(bytes);
      return true;
    } catch (e) {
      debugPrint('Erro ao imprimir lista de clientes: $e');
      return false;
    }
  }

  /// Imprime relatório formatado
  Future<bool> printReport({
    required String title,
    required String date,
    required List<Map<String, String>> items,
    required Map<String, String> totals,
  }) async {
    if (!_isConnected || _writeCharacteristic == null) {
      debugPrint('Impressora não conectada');
      return false;
    }

    try {
      List<int> bytes = [];

      // Reset
      bytes.addAll(EscPosCommands.reset);

      // Cabeçalho
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(EscPosCommands.doubleHeightOn);
      bytes.addAll(_textToBytes(title));
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.normalSize);
      bytes.addAll(_textToBytes('Data: $date'));
      bytes.addAll(EscPosCommands.lineFeed);

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Alinha à esquerda para itens
      bytes.addAll(EscPosCommands.alignLeft);

      // Itens
      for (var item in items) {
        final name = item['name'] ?? '';
        final qty = item['qty'] ?? '';

        final qtyStr = qty.padLeft(4);
        final nameMaxLen = _printerWidth - qtyStr.length - 1;
        final nameStr = name.length > nameMaxLen 
            ? name.substring(0, nameMaxLen) 
            : name.padRight(nameMaxLen);
        
        bytes.addAll(_textToBytes('$nameStr $qtyStr'));
        bytes.addAll(EscPosCommands.lineFeed);
      }

      // Linha divisória
      bytes.addAll(_textToBytes(EscPosCommands.horizontalLine(_printerWidth)));
      bytes.addAll(EscPosCommands.lineFeed);

      // Totais
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(_textToBytes('TOTAIS:'));
      bytes.addAll(EscPosCommands.lineFeed);
      
      totals.forEach((key, value) {
        final keyStr = key.padRight(_printerWidth - value.length);
        bytes.addAll(_textToBytes('$keyStr$value'));
        bytes.addAll(EscPosCommands.lineFeed);
      });

      // Avanço mínimo antes do corte
      bytes.addAll(EscPosCommands.lineFeed);
      bytes.addAll(EscPosCommands.partialCut);

      await _sendData(bytes);
      return true;
    } catch (e) {
      debugPrint('Erro ao imprimir relatório: $e');
      return false;
    }
  }

  /// Envia dados para a impressora em chunks para evitar overflow
  Future<void> _sendData(List<int> bytes) async {
    if (_writeCharacteristic == null || _connectedDevice == null) {
      throw Exception('Impressora não conectada ou característica de escrita ausente');
    }

    // Tenta obter o MTU atual, se não conseguir usa o padrão seguro do Bluetooth (23 - 3 de overhead = 20)
    int mtu = 20;
    try {
      // O flutter_blue_plus permite ler o MTU atual
      mtu = await _connectedDevice!.mtu.first;
      // Descontamos 3 bytes de overhead do protocolo BLE
      mtu = mtu - 3;
      if (mtu < 20) mtu = 20;
      debugPrint('Usando chunk size (MTU-3): $mtu');
    } catch (e) {
      debugPrint('Não foi possível obter MTU, usando 20: $e');
      mtu = 20;
    }

    for (int i = 0; i < bytes.length; i += mtu) {
      if (!_isConnected) {
        throw Exception('Conexão perdida durante a impressão');
      }

      final end = (i + mtu < bytes.length) ? i + mtu : bytes.length;
      final chunk = bytes.sublist(i, end);
      
      try {
        // Tenta escrever com resposta para garantir que o buffer da impressora não estoure
        await _writeCharacteristic!.write(chunk, withoutResponse: false, timeout: 5);
      } catch (e) {
        debugPrint('Erro ao escrever chunk (tentando sem resposta): $e');
        try {
          await _writeCharacteristic!.write(chunk, withoutResponse: true);
        } catch (e2) {
          throw Exception('Falha crítica ao enviar dados para a impressora: $e2');
        }
      }
      
      // Pequeno delay entre chunks para dar tempo da impressora processar
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Mostra dialog para selecionar impressora Bluetooth
  static Future<BluetoothDevice?> showPrinterSelector(BuildContext context) async {
    final service = BluetoothPrinterService.instance;
    
    // Verifica se Bluetooth está ligado
    if (!await service.isBluetoothOn()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, ligue o Bluetooth do dispositivo'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    // Solicita permissões explicitamente antes de abrir o seletor
    await service.requestPermissions();

    if (!context.mounted) return null;

    return showDialog<BluetoothDevice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.bluetooth, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Expanded(child: Text('Selecionar Impressora')),
                if (service.isScanning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () async {
                      await service.startScan();
                      setState(() {});
                      // Aguarda um pouco e para o scan ou deixa o timeout agir
                      Future.delayed(const Duration(seconds: 4), () {
                        if (context.mounted) setState(() {});
                      });
                    },
                    tooltip: 'Procurar novos dispositivos',
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (service.isConnected && service.connectedDevice != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
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
                              'Conectado: ${service.connectedDevice!.platformName}',
                              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const Text(
                    'Dispositivos encontrados:',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  Flexible(
                    child: FutureBuilder<List<BluetoothDevice>>(
                      future: service.getBondedDevices(),
                      builder: (context, snapshot) {
                        List<BluetoothDevice> bonded = snapshot.data ?? [];
                        
                        // Adiciona dispositivos do scan que ainda não estão na lista de bonded
                        List<BluetoothDevice> scanned = service.scanResults
                            .map((r) => r.device)
                            .where((d) => !bonded.any((b) => b.remoteId == d.remoteId))
                            .toList();
                        
                        List<BluetoothDevice> all = [...bonded, ...scanned];

                        if (all.isEmpty && !service.isScanning) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'Nenhuma impressora encontrada.\nCertifique-se que está ligada e pareada.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: all.length,
                          itemBuilder: (context, index) {
                            final device = all[index];
                            final isCurrentlyConnected = service.connectedDevice?.remoteId == device.remoteId;
                            final name = device.platformName.isNotEmpty ? device.platformName : 'Dispositivo sem nome';
                            
                            // Frequentemente impressoras térmicas têm nomes como "MTP-II", "GP-58", "Bluetooth Printer"
                            final isLikelyPrinter = name.toLowerCase().contains('print') || 
                                                  name.toLowerCase().contains('mtp') ||
                                                  name.toUpperCase().contains('GS-');

                            return ListTile(
                              leading: Icon(
                                isLikelyPrinter ? Icons.print : Icons.bluetooth,
                                color: isCurrentlyConnected ? Colors.green : Colors.blue.shade700,
                                size: 22,
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: isCurrentlyConnected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(device.remoteId.toString(), style: const TextStyle(fontSize: 11)),
                              trailing: isCurrentlyConnected
                                  ? const Icon(Icons.check, color: Colors.green)
                                  : const Icon(Icons.chevron_right, size: 18),
                              onTap: () async {
                                if (service.isScanning) await service.stopScan();
                                if (context.mounted) Navigator.pop(context, device);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (service.isConnected)
                TextButton(
                  onPressed: () async {
                    await service.disconnect();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Desconectar', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () async {
                  if (service.isScanning) await service.stopScan();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Cancelar'),
              ),
            ],
          );
        }
      ),
    );
  }

  /// Conecta e imprime em uma única operação
  static Future<bool> connectAndPrint(
    BuildContext context, {
    required Future<bool> Function() printFunction,
    bool disconnectAfter = true,
  }) async {
    final service = BluetoothPrinterService.instance;

    // Se não está conectado, mostra seletor
    if (!service.isConnected) {
      final device = await showPrinterSelector(context);
      if (device == null) return false;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conectando a impressora...'), duration: Duration(seconds: 2)),
        );
      }

      final connected = await service.connect(device);
      if (!connected) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Falha ao conectar. Tente parear novamente ou reiniciar a impressora.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }

    // Imprime e desconecta opcionalmente
    bool success = false;
    try {
      success = await printFunction();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Impresso com sucesso!' : 'Falha na impressao (verifique a conexao)'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro durante a execucao da impressao: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      success = false;
    } finally {
      // Desconecta se solicitado
      if (disconnectAfter) {
        await service.disconnect();
      }
    }
    return success;
  }
}
