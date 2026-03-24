import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:intl/intl.dart';
import '../models/cliente_model.dart';
import '../services/supabase_service.dart';
import '../services/bluetooth_printer_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  List<Cliente> clientes = [];
  bool isLoading = true;
  bool isEditing = false;
  
  // Controllers
  final _formKey = GlobalKey<FormState>();
  final _razaoSocialController = TextEditingController();
  final _contatoController = TextEditingController();
  final _fantasiaController = TextEditingController();
  final _cnpjCpfController = TextEditingController();
  final _cepController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _bairroController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _valorGeloDoPortoController = TextEditingController();
  
  String? _editingId;
  String _tipoCliente = 'PF';
  bool _isAtivo = true;
  bool _isGeloDoPorto = false;
  String _searchQuery = '';

  // Máscaras
  final _cpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
  );
  
  final _cnpjFormatter = MaskTextInputFormatter(
    mask: '##.###.###/####-##',
    filter: {"#": RegExp(r'[0-9]')},
  );
  
  final _cepFormatter = MaskTextInputFormatter(
    mask: '#####-###',
    filter: {"#": RegExp(r'[0-9]')},
  );
  
  final _telefoneFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  final _currencyFormatter = CurrencyInputFormatter();

  @override
  void initState() {
    super.initState();
    _fetchClientes();
  }

  @override
  void dispose() {
    _razaoSocialController.dispose();
    _contatoController.dispose();
    _fantasiaController.dispose();
    _cnpjCpfController.dispose();
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _cidadeController.dispose();
    _bairroController.dispose();
    _telefoneController.dispose();
    _valorGeloDoPortoController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientes() async {
    setState(() => isLoading = true);
    try {
      final response = await SupabaseService.client
          .from('clientes')
          .select()
          .eq('is_excluido', false)
          .order('razao_social', ascending: true);
      
      setState(() {
        clientes = (response as List).map((e) => Cliente.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Erro ao carregar clientes: $e', isError: true);
    }
  }

  Future<void> _buscarCep(String cep) async {
    final cleanCep = cep.replaceAll(RegExp(r'\D'), '');
    if (cleanCep.length != 8) return;

    try {
      final response = await http.get(
        Uri.parse('https://viacep.com.br/ws/$cleanCep/json/'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] != true) {
          setState(() {
            _logradouroController.text = data['logradouro'] ?? '';
            _bairroController.text = data['bairro'] ?? '';
            _cidadeController.text = data['localidade'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    }
  }

  void _clearForm() {
    _editingId = null;
    _tipoCliente = 'PF';
    _isAtivo = true;
    _isGeloDoPorto = false;
    _searchQuery = '';
    _razaoSocialController.clear();
    _contatoController.clear();
    _fantasiaController.clear();
    _cnpjCpfController.clear();
    _cepController.clear();
    _logradouroController.clear();
    _numeroController.clear();
    _complementoController.clear();
    _cidadeController.clear();
    _bairroController.clear();
    _telefoneController.clear();
    _valorGeloDoPortoController.clear();
    _cpfFormatter.clear();
    _cnpjFormatter.clear();
    _cepFormatter.clear();
    _telefoneFormatter.clear();
  }

  String _formatCpfCnpj(String? value) {
    if (value == null || value.isEmpty) return '';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 11) {
      // CPF
      String result = '';
      for (int i = 0; i < digits.length && i < 11; i++) {
        if (i == 3 || i == 6) result += '.';
        if (i == 9) result += '-';
        result += digits[i];
      }
      return result;
    } else {
      // CNPJ
      String result = '';
      for (int i = 0; i < digits.length && i < 14; i++) {
        if (i == 2 || i == 5) result += '.';
        if (i == 8) result += '/';
        if (i == 12) result += '-';
        result += digits[i];
      }
      return result;
    }
  }

  String _formatCep(String? value) {
    if (value == null || value.isEmpty) return '';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 5) {
      return '${digits.substring(0, 5)}-${digits.substring(5, digits.length.clamp(5, 8))}';
    }
    return digits;
  }

  String _formatTelefone(String? value) {
    if (value == null || value.isEmpty) return '';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 11) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
    } else if (digits.length >= 10) {
      return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6, 10)}';
    }
    return digits;
  }

  void _editCliente(Cliente cliente) {
    _editingId = cliente.id;
    _tipoCliente = cliente.tipoCliente;
    _isAtivo = cliente.isAtivo;
    _isGeloDoPorto = cliente.isGeloDoPorto;
    _razaoSocialController.text = cliente.razaoSocial;
    _contatoController.text = cliente.contato ?? '';
    _fantasiaController.text = cliente.fantasia ?? '';
    _cnpjCpfController.text = _formatCpfCnpj(cliente.cnpjCpf);
    _cepController.text = _formatCep(cliente.cep);
    _logradouroController.text = cliente.logradouro ?? '';
    _numeroController.text = cliente.numero ?? '';
    _complementoController.text = cliente.complemento ?? '';
    _cidadeController.text = cliente.cidade ?? '';
    _bairroController.text = cliente.bairro ?? '';
    _telefoneController.text = _formatTelefone(cliente.telefone);
    
    if (cliente.valorGeloDoPorto != null) {
      _valorGeloDoPortoController.text = _currencyFormatter.formatDouble(cliente.valorGeloDoPorto!);
    } else {
      _valorGeloDoPortoController.text = '';
    }
    
    setState(() => isEditing = true);
  }

  Future<void> _saveCliente() async {
    if (!_formKey.currentState!.validate()) return;

    final cliente = Cliente(
      id: _editingId,
      tipoCliente: _tipoCliente,
      razaoSocial: _razaoSocialController.text,
      contato: _contatoController.text.isNotEmpty ? _contatoController.text : null,
      fantasia: _fantasiaController.text.isNotEmpty ? _fantasiaController.text : null,
      cnpjCpf: _cnpjCpfController.text,
      cep: _cepController.text,
      logradouro: _logradouroController.text.isNotEmpty ? _logradouroController.text : null,
      numero: _numeroController.text.isNotEmpty ? _numeroController.text : null,
      complemento: _complementoController.text.isNotEmpty ? _complementoController.text : null,
      cidade: _cidadeController.text.isNotEmpty ? _cidadeController.text : null,
      bairro: _bairroController.text.isNotEmpty ? _bairroController.text : null,
      telefone: _telefoneController.text,
      isAtivo: _isAtivo,
      isGeloDoPorto: _isGeloDoPorto,
      valorGeloDoPorto: _isGeloDoPorto ? _currencyFormatter.parseDouble(_valorGeloDoPortoController.text) : null,
    );

    try {
      if (_editingId != null) {
        await SupabaseService.client
            .from('clientes')
            .update(cliente.toJson())
            .eq('id', _editingId!);
        _showSnackBar('Cliente atualizado com sucesso!');
      } else {
        await SupabaseService.client
            .from('clientes')
            .insert(cliente.toJson());
        _showSnackBar('Cliente cadastrado com sucesso!');
      }

      _clearForm();
      setState(() => isEditing = false);
      _fetchClientes();
    } catch (e) {
      _showSnackBar('Erro ao salvar cliente: $e', isError: true);
    }
  }

  Future<void> _deleteCliente(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Deseja realmente excluir este cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.client
            .from('clientes')
            .update({'is_excluido': true})
            .eq('id', id);
        _showSnackBar('Cliente excluído com sucesso!');
        _fetchClientes();
      } catch (e) {
        _showSnackBar('Erro ao excluir cliente: $e', isError: true);
      }
    }
  }

  Future<void> _printClientesPdf(List<Cliente> filteredClientes) async {
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
          ),
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('LISTA DE CLIENTES', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Nome / Razão Social', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('CNPJ/CPF', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Telefone', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  ],
                ),
                ...filteredClientes.map((cliente) => pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(cliente.razaoSocial, style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_formatCpfCnpj(cliente.cnpjCpf), style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_formatTelefone(cliente.telefone), style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(cliente.isAtivo ? 'Ativo' : 'Inativo', style: const pw.TextStyle(fontSize: 9))),
                  ],
                )).toList(),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Lista_Clientes_${DateFormat('ddMMyyyy').format(DateTime.now())}',
      );
    } catch (e) {
      _showSnackBar('Erro ao gerar PDF: $e', isError: true);
    }
  }

  Future<void> _printClientesBluetooth(List<Cliente> filteredClientes) async {
    if (kIsWeb) {
      _showSnackBar('Impressão Bluetooth não é suportada no navegador. Use PDF.', isError: true);
      return;
    }
    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        final items = filteredClientes.map((c) => {
          'name': c.razaoSocial,
          'info': '${_formatTelefone(c.telefone)} ${c.isAtivo ? "(Ativo)" : "(Inativo)"}',
        }).toList();

        return BluetoothPrinterService.instance.printClientes(items: items);
      },
    );

    if (success && mounted) {
      _showReprintDialog(filteredClientes);
    }
  }

  void _showReprintDialog(List<Cliente> filteredClientes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impressão Concluída'),
        content: const Text('Deseja imprimir novamente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Não')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _printClientesBluetooth(filteredClientes);
            },
            child: const Text('Sim'),
          ),
        ],
      ),
    );
  }

  void _showPrintOptions() {
    final filteredClientes = clientes.where((c) {
      return _searchQuery.isEmpty || 
          c.razaoSocial.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredClientes.isEmpty) {
      _showSnackBar('Nenhum cliente para imprimir', isError: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Opções de Impressão',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF (Impressão / Salvar)'),
              onTap: () {
                Navigator.pop(context);
                _printClientesPdf(filteredClientes);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.blue),
              title: const Text('Térmica (Bluetooth)'),
              onTap: () {
                Navigator.pop(context);
                _printClientesBluetooth(filteredClientes);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 850;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Card(
          margin: EdgeInsets.all(isMobile ? 8 : 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Design
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? (_editingId != null ? 'Editando Cliente' : 'Novo Cliente') : 'Cadastro de Clientes',
                            style: TextStyle(
                              fontSize: isMobile ? 22 : 26, 
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (!isEditing)
                            Text(
                              'Gerencie sua base de clientes com facilidade',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                      if (!isEditing)
                        Padding(
                          padding: EdgeInsets.only(top: isMobile ? 16 : 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 12, // Espaçamento vertical para celular
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  _clearForm();
                                  setState(() => isEditing = true);
                                },
                                icon: const Icon(Icons.person_add_rounded, size: 20),
                                label: const Text('Novo Cliente'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              IconButton(
                                onPressed: _showPrintOptions,
                                icon: const Icon(Icons.print_rounded, color: Color(0xFF64748B)),
                                tooltip: 'Imprimir Clientes',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.all(12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Form or Table
                if (isEditing)
                  _buildForm()
                else if (isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _buildTable(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 850;
    final fieldWidth = isMobile ? screenWidth : 400.0;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Ativo / Inativo (No topo como solicitado, apenas o Switch)
          isMobile 
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Cliente Gelo do Porto:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Switch(
                        value: _isGeloDoPorto,
                        activeColor: const Color(0xFF4F46E5),
                        onChanged: (bool value) {
                          setState(() {
                            _isGeloDoPorto = value;
                          });
                        },
                      ),
                      if (_isGeloDoPorto) ...[
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          height: 40,
                          child: TextFormField(
                            controller: _valorGeloDoPortoController,
                            decoration: _inputDecoration('Valor').copyWith(
                              prefixText: 'R\$ ',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _currencyFormatter,
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Ativo:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Switch(
                        value: _isAtivo,
                        activeColor: const Color(0xFF4F46E5),
                        onChanged: (bool value) {
                          setState(() {
                            _isAtivo = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  const Text('Cliente Gelo do Porto:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isGeloDoPorto,
                    activeColor: const Color(0xFF4F46E5),
                    onChanged: (bool value) {
                      setState(() {
                        _isGeloDoPorto = value;
                      });
                    },
                  ),
                  if (_isGeloDoPorto) ...[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 100,
                      height: 40,
                      child: TextFormField(
                        controller: _valorGeloDoPortoController,
                        decoration: _inputDecoration('Valor').copyWith(
                          prefixText: 'R\$ ',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _currencyFormatter,
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 24),
                  const Text('Ativo:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isAtivo,
                    activeColor: const Color(0xFF4F46E5),
                    onChanged: (bool value) {
                      setState(() {
                        _isAtivo = value;
                      });
                    },
                  ),
                ],
              ),
          const SizedBox(height: 16),
          if (isMobile)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // Tipo
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<String>(
                    value: _tipoCliente,
                    decoration: _inputDecoration('Tipo de Cliente'),
                    items: const [
                      DropdownMenuItem(value: 'PF', child: Text('Pessoa Física')),
                      DropdownMenuItem(value: 'PJ', child: Text('Pessoa Jurídica')),
                    ],
                    onChanged: (value) => setState(() => _tipoCliente = value ?? 'PF'),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _razaoSocialController,
                    decoration: _inputDecoration('Razão Social / Nome completo'),
                    validator: (v) => v?.isEmpty == true ? 'Campo obrigatório' : null,
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _contatoController,
                    decoration: _inputDecoration('Contato / Responsável'),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _fantasiaController,
                    decoration: _inputDecoration('Nome Fantasia / Apelido'),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _cnpjCpfController,
                    decoration: _inputDecoration('CNPJ / CPF'),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _tipoCliente == 'PF' ? _cpfFormatter : _cnpjFormatter,
                    ],
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _cepController,
                    decoration: _inputDecoration('CEP').copyWith(
                      suffixIcon: const Icon(Icons.search, size: 20),
                    ),
                    inputFormatters: [_cepFormatter],
                    onChanged: (value) {
                      if (value.replaceAll(RegExp(r'\D'), '').length == 8) {
                        _buscarCep(value);
                      }
                    },
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cidadeController,
                        decoration: _inputDecoration('Cidade'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _bairroController,
                        decoration: _inputDecoration('Bairro'),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _logradouroController,
                    decoration: _inputDecoration('Rua / Logradouro'),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _numeroController,
                    decoration: _inputDecoration('Nº'),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _telefoneController,
                    decoration: _inputDecoration('Telefone / WhatsApp'),
                    inputFormatters: [_telefoneFormatter],
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                // Seção: Informações Básicas
                _buildSectionHeader('Informações Básicas', Icons.person_outline),
                Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _tipoCliente,
                        decoration: _inputDecoration('Tipo de Cliente'),
                        items: const [
                          DropdownMenuItem(value: 'PF', child: Text('Pessoa Física')),
                          DropdownMenuItem(value: 'PJ', child: Text('Pessoa Jurídica')),
                        ],
                        onChanged: (value) => setState(() => _tipoCliente = value ?? 'PF'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _razaoSocialController,
                        decoration: _inputDecoration('Razão Social / Nome completo'),
                        validator: (v) => v?.isEmpty == true ? 'Campo obrigatório' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cnpjCpfController,
                        decoration: _inputDecoration('CNPJ / CPF'),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _tipoCliente == 'PF' ? _cpfFormatter : _cnpjFormatter,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _fantasiaController,
                        decoration: _inputDecoration('Nome Fantasia / Apelido'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contatoController,
                  decoration: _inputDecoration('Contato / Responsável'),
                ),
                
                const SizedBox(height: 32),
                
                // Seção: Endereço e Localização
                _buildSectionHeader('Endereço e Localização', Icons.location_on_outlined),
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: TextFormField(
                        controller: _cepController,
                        decoration: _inputDecoration('CEP').copyWith(
                          suffixIcon: const Icon(Icons.search, size: 20),
                        ),
                        inputFormatters: [_cepFormatter],
                        onChanged: (value) {
                          if (value.replaceAll(RegExp(r'\D'), '').length == 8) {
                            _buscarCep(value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _cidadeController,
                        decoration: _inputDecoration('Cidade'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _bairroController,
                        decoration: _inputDecoration('Bairro'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _logradouroController,
                        decoration: _inputDecoration('Rua / Logradouro'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _numeroController,
                        decoration: _inputDecoration('Nº'),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Seção: Contato Adicional
                _buildSectionHeader('Contato e Status', Icons.contact_phone_outlined),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telefoneController,
                        decoration: _inputDecoration('Telefone / WhatsApp'),
                        inputFormatters: [_telefoneFormatter],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveCliente,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _clearForm();
                    setState(() => isEditing = false);
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final filteredClientes = clientes.where((c) {
      // Filtro de Nome
      // Filtro de Nome
      return _searchQuery.isEmpty || 
          c.razaoSocial.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            height: 45,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nome...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
        ),
        Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Nome / Razão Social', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('CNPJ/CPF', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Bairro', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Cidade', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Gelo do Porto', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: filteredClientes.map((cliente) {
                return DataRow(cells: [
                  DataCell(Text(cliente.razaoSocial)),
                  DataCell(Text(cliente.tipoCliente)),
                  DataCell(Text(_formatCpfCnpj(cliente.cnpjCpf))),
                  DataCell(Text(cliente.bairro ?? '')),
                  DataCell(Text(cliente.cidade ?? '')),
                  DataCell(
                    cliente.isGeloDoPorto 
                      ? Text('Sim (${NumberFormat.simpleCurrency(locale: 'pt_BR').format(cliente.valorGeloDoPorto ?? 0)})', 
                          style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold))
                      : const Text('Não')
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: cliente.isAtivo ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cliente.isAtivo ? 'Ativo' : 'Inativo',
                        style: TextStyle(
                          color: cliente.isAtivo ? const Color(0xFF166534) : const Color(0xFF991B1B),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF94A3B8), size: 20),
                        onPressed: () => _editCliente(cliente),
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 20),
                        onPressed: () => _deleteCliente(cliente.id!),
                        tooltip: 'Excluir',
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            width: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.selection.baseOffset == 0) return newValue;

    double value = double.parse(newValue.text);
    final formatter = NumberFormat.simpleCurrency(locale: 'pt_BR', name: '');
    String newText = formatter.format(value / 100);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  double? parseDouble(String text) {
    if (text.isEmpty) return null;
    String cleanText = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleanText);
  }

  String formatDouble(double value) {
    final formatter = NumberFormat.simpleCurrency(locale: 'pt_BR', name: '');
    return formatter.format(value);
  }
}
