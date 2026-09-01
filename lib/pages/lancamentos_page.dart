import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/cliente_model.dart';
import '../models/produto_model.dart';
import '../models/lancamento_model.dart';
import '../services/supabase_service.dart';
import '../services/bluetooth_printer_service.dart';

class LancamentosPage extends StatefulWidget {
  const LancamentosPage({super.key});

  @override
  State<LancamentosPage> createState() => _LancamentosPageState();
}

class _LancamentosPageState extends State<LancamentosPage> {
  List<LancamentoCabecalho> lancamentos = [];
  List<Cliente> clientes = [];
  List<Produto> produtos = [];
  List<LancamentoItem> itens = [];
  
  bool isLoading = true;
  bool isAdding = false;
  
  String? _editingId;
  String? _selectedClienteId;
  String _clienteSearch = '';
  DateTime _dtEmissao = DateTime.now();
  String _tipoPagamento = 'A Vista';
  bool _showClienteDropdown = false;
  final TextEditingController _clienteSearchController = TextEditingController();

  // Item atual
  String? _selectedProdutoId;
  double _itemVrCusto = 0;
  double _itemVrVenda = 0;
  double _itemVrDesconto = 0;
  int _itemQtd = 1;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _numberFormat = NumberFormat('#,##0.00', 'pt_BR');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _clienteSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    try {
      final clientesResponse = await SupabaseService.client
          .from('clientes')
          .select()
          .eq('is_excluido', false)
          .eq('is_ativo', true);
      
      final produtosResponse = await SupabaseService.client
          .from('produtos')
          .select()
          .eq('is_excluido', false)
          .eq('is_ativo', true);
      
      final lancamentosResponse = await SupabaseService.client
          .from('lancto_cabecalho')
          .select('*, clientes(razao_social)')
          .eq('is_excluido', false)
          .order('created_at', ascending: false);

      setState(() {
        clientes = (clientesResponse as List)
            .map((e) => Cliente.fromJson(e))
            .toList()
          ..sort((a, b) => a.razaoSocial.compareTo(b.razaoSocial));
        produtos = (produtosResponse as List).map((e) => Produto.fromJson(e)).toList();
        lancamentos = (lancamentosResponse as List).map((e) => LancamentoCabecalho.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Erro ao carregar dados: $e', isError: true);
    }
  }

  void _clearForm() {
    _editingId = null;
    _selectedClienteId = null;
    _clienteSearch = '';
    _clienteSearchController.clear();
    _dtEmissao = DateTime.now();
    _tipoPagamento = 'A Vista';
    itens = [];
    _clearItemForm();
  }

  void _clearItemForm() {
    _selectedProdutoId = null;
    _itemVrCusto = 0;
    _itemVrVenda = 0;
    _itemVrDesconto = 0;
    _itemQtd = 1;
  }

  void _updateItemPrices(Produto p) {
    if (_selectedClienteId != null) {
      final cliente = clientes.firstWhere(
        (c) => c.id == _selectedClienteId,
        orElse: () => Cliente(tipoCliente: 'PF', razaoSocial: '', isGeloDoPorto: false),
      );
      if (cliente.isGeloDoPorto) {
        _itemVrCusto = 0;
        _itemVrVenda = cliente.valorGeloDoPorto ?? p.vrVenda;
        return;
      }
    }
    _itemVrCusto = p.vrCusto;
    _itemVrVenda = p.vrVenda;
  }

  double get _totalVenda => itens.fold(0, (sum, item) => sum + item.subtotal);
  double get _totalCusto => itens.fold(0, (sum, item) => sum + item.custoTotal);
  double get _totalLucro => _totalVenda - _totalCusto;

  void _addItem() {
    if (_selectedProdutoId == null) return;

    final produto = produtos.firstWhere((p) => p.id == _selectedProdutoId);

    // Recalcula preço unitário com base no cliente selecionado,
    // garantindo que clientes Gelo do Porto usem o valor cadastrado.
    double vrCusto = _itemVrCusto;
    double vrVenda = _itemVrVenda;
    if (_selectedClienteId != null) {
      final cliente = clientes.firstWhere(
        (c) => c.id == _selectedClienteId,
        orElse: () => Cliente(tipoCliente: 'PF', razaoSocial: '', isGeloDoPorto: false),
      );
      if (cliente.isGeloDoPorto) {
        vrCusto = 0;
        vrVenda = cliente.valorGeloDoPorto ?? produto.vrVenda;
      }
    }

    final newItem = LancamentoItem(
      produtoId: _selectedProdutoId!,
      produtoNome: produto.nome,
      vrCusto: vrCusto,
      vrVenda: vrVenda,
      vrDesconto: _itemVrDesconto,
      quantidade: _itemQtd,
    );

    setState(() {
      itens = [...itens, newItem];
      _clearItemForm();
    });
  }

  void _removeItem(int index) {
    setState(() {
      itens = List.from(itens)..removeAt(index);
    });
  }

  Future<void> _editLancamento(LancamentoCabecalho lancamento) async {
    _editingId = lancamento.id;
    _selectedClienteId = lancamento.clienteId;
    _dtEmissao = lancamento.dtEmissao;
    _tipoPagamento = lancamento.tipoPagamento ?? 'A Vista';
    
    final cliente = clientes.firstWhere(
      (c) => c.id == lancamento.clienteId,
      orElse: () => Cliente(tipoCliente: 'PF', razaoSocial: ''),
    );
    _clienteSearch = cliente.razaoSocial;
    _clienteSearchController.text = _clienteSearch;

    // Fetch items
    try {
      final itemsResponse = await SupabaseService.client
          .from('lancto_itens')
          .select('*, produtos(nome)')
          .eq('cabecalho_id', lancamento.id!);

      setState(() {
        itens = (itemsResponse as List).map((e) => LancamentoItem.fromJson(e)).toList();
        isAdding = true;
      });
    } catch (e) {
      _showSnackBar('Erro ao carregar itens: $e', isError: true);
    }
  }

  Future<void> _saveLancamento() async {
    if (_selectedClienteId == null || itens.isEmpty) {
      _showSnackBar('Selecione um cliente e adicione pelo menos um item.', isError: true);
      return;
    }

    try {
      // Garante que itens de clientes Gelo do Porto usem o valor cadastrado no cliente.
      final cliente = clientes.firstWhere(
        (c) => c.id == _selectedClienteId,
        orElse: () => Cliente(tipoCliente: 'PF', razaoSocial: '', isGeloDoPorto: false),
      );
      if (cliente.isGeloDoPorto) {
        itens = itens.map((item) {
          final produto = produtos.firstWhere(
            (p) => p.id == item.produtoId,
            orElse: () => Produto(nome: item.produtoNome ?? '', vrCusto: item.vrCusto, vrVenda: item.vrVenda),
          );
          return LancamentoItem(
            produtoId: item.produtoId,
            produtoNome: item.produtoNome,
            vrCusto: 0,
            vrVenda: cliente.valorGeloDoPorto ?? produto.vrVenda,
            vrDesconto: item.vrDesconto,
            quantidade: item.quantidade,
          );
        }).toList();
      }

      String? cabecalhoId = _editingId;

      final headPayload = {
        'cliente_id': _selectedClienteId,
        'dt_emissao': _dtEmissao.toIso8601String().split('T')[0],
        'tipo_pagamento': _tipoPagamento,
        'vr_total_venda': _totalVenda,
        'vr_total_custo': _totalCusto,
        'vr_total_lucro': _totalLucro,
      };

      if (cabecalhoId != null) {
        await SupabaseService.client
            .from('lancto_cabecalho')
            .update(headPayload)
            .eq('id', cabecalhoId);

        // Delete old items
        await SupabaseService.client
            .from('lancto_itens')
            .delete()
            .eq('cabecalho_id', cabecalhoId);
      } else {
        final response = await SupabaseService.client
            .from('lancto_cabecalho')
            .insert(headPayload)
            .select();
        cabecalhoId = response[0]['id'].toString();
      }

      // Insert items
      final itensToInsert = itens.map((item) {
        final map = item.toJson();
        map.remove('id'); // Remove ID to avoid Postgrest null constraint issues
        map['cabecalho_id'] = cabecalhoId;
        return map;
      }).toList();

      await SupabaseService.client.from('lancto_itens').insert(itensToInsert);

      _showSnackBar(_editingId != null ? 'Lançamento atualizado!' : 'Lançamento salvo!');
      _clearForm();
      setState(() => isAdding = false);
      _fetchData();
    } catch (e) {
      _showSnackBar('Erro ao salvar lançamento: $e', isError: true);
    }
  }

  Future<void> _deleteLancamento(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Deseja realmente excluir este lançamento?'),
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
            .from('lancto_cabecalho')
            .update({'is_excluido': true})
            .eq('id', id);
        _showSnackBar('Lançamento excluído!');
        _fetchData();
      } catch (e) {
        _showSnackBar('Erro ao excluir: $e', isError: true);
      }
    }
  }

  Future<void> _printLancamento(LancamentoCabecalho lancamento) async {
    try {
      // Fetch items for printing
    final itemsResponse = await SupabaseService.client
        .from('lancto_itens')
        .select('*, produtos(nome, vr_venda)')
        .eq('cabecalho_id', lancamento.id!);

    final List<dynamic> rawItems = itemsResponse as List;
    final printItens = rawItems.map((e) => LancamentoItem.fromJson(e)).toList();

    // Fetch full customer details
    final clienteResponse = await SupabaseService.client
        .from('clientes')
        .select()
        .eq('id', lancamento.clienteId)
        .single();
    final cliente = Cliente.fromJson(clienteResponse);

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document();
    // Calculate total including discounts
    double totalRecibo = printItens.fold(0, (sum, item) => sum + item.subtotal);

    pdf.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 10,
          marginRight: 2,
          marginTop: 10,
          marginBottom: 10,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'RECIBO',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'D.M REPRESENTANTE DO GELO DO PORTO.',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      'CNPJ: 52.162.684/0001-21',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'ROD. OSWALDO CRUZ 6365',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.Divider(),
              pw.Text('Cliente: ${lancamento.clienteNome ?? ""}'),
              if (cliente.cnpjCpf != null && cliente.cnpjCpf!.isNotEmpty)
                pw.Text('CNPJ/CPF: ${cliente.cnpjCpf}'),
              if (cliente.logradouro != null && cliente.logradouro!.isNotEmpty)
                pw.Text('Endereço: ${cliente.logradouro}, ${cliente.numero ?? ""} - ${cliente.bairro ?? ""}, ${cliente.cidade ?? ""}'),
              pw.Text('Data: ${_dateFormat.format(lancamento.dtEmissao)}'),
              pw.Text('Pagamento: ${lancamento.tipoPagamento ?? "Nao informado"}'),
              pw.Divider(),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Expanded(flex: 2, child: pw.Text('QTD', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 5, child: pw.Text('ITEM', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 4, child: pw.Text('VALOR', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 4, child: pw.Text('TOTAL', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                ],
              ),
              pw.Divider(),
              ...rawItems.asMap().entries.map((entry) {
                final index = entry.key;
                final rawItem = entry.value;
                final item = printItens[index];
                
                // Use unit price after discount
                final unitPrice = item.vrVenda - item.vrDesconto;
                final printableSubtotal = item.subtotal;

                return pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 2, 
                        child: pw.Text('${item.quantidade}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9), maxLines: 1),
                      ),
                      pw.Expanded(
                        flex: 5, 
                        child: pw.Text(item.produtoNome ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Expanded(
                        flex: 4, 
                        child: pw.Text(_numberFormat.format(unitPrice), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9), maxLines: 1),
                      ),
                      pw.Expanded(
                        flex: 4, 
                        child: pw.Text(_numberFormat.format(printableSubtotal), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9), maxLines: 1),
                      ),
                    ],
                  ),
                );
              }),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'TOTAL: ${_currencyFormat.format(totalRecibo)}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Center(child: pw.Text('Obrigado pela preferência!', style: const pw.TextStyle(fontSize: 10))),
              pw.SizedBox(height: 30),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      child: pw.Divider(thickness: 1),
                    ),
                    pw.Text('Assinatura', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    _showReprintDialog(lancamento, () => _printLancamento(lancamento));
    } catch (e) {
      _showSnackBar('Erro ao gerar PDF: $e', isError: true);
    }
  }

  Future<void> _printBluetoothLancamento(LancamentoCabecalho lancamento) async {
    if (kIsWeb) {
      _showSnackBar('Impressão Bluetooth não é suportada no navegador. Use "Imprimir PDF".', isError: true);
      return;
    }

    try {
      // Fetch items for printing
    final itemsResponse = await SupabaseService.client
        .from('lancto_itens')
        .select('*, produtos(nome, vr_venda)')
        .eq('cabecalho_id', lancamento.id!);

    final List<dynamic> rawItems = itemsResponse as List;
    final printItens = rawItems.map((e) => LancamentoItem.fromJson(e)).toList();

    // Fetch full customer details
    final clienteResponse = await SupabaseService.client
        .from('clientes')
        .select()
        .eq('id', lancamento.clienteId)
        .single();
    final cliente = Cliente.fromJson(clienteResponse);

    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        double totalRecibo = 0;
        final items = printItens.map((item) {
          final unitPrice = item.vrVenda - item.vrDesconto;
          final printableSubtotal = item.subtotal;
          totalRecibo += printableSubtotal;

          return {
            'name': item.produtoNome ?? '',
            'qty': '${item.quantidade}',
            'price': _currencyFormat.format(unitPrice),
            'total': _currencyFormat.format(printableSubtotal),
          };
        }).toList();

        String subtitle = 'D.M REPRESENTANTE DO GELO\nDO PORTO.\nCNPJ: 52.162.684/0001-21\nROD. OSWALDO CRUZ 6365\n\nCliente: ${lancamento.clienteNome ?? ""}';
        
        if (cliente.cnpjCpf != null && cliente.cnpjCpf!.isNotEmpty) {
          subtitle += '\nCNPJ/CPF: ${cliente.cnpjCpf}';
        }
        
        if (cliente.logradouro != null && cliente.logradouro!.isNotEmpty) {
          subtitle += '\nEndereço: ${cliente.logradouro}, ${cliente.numero ?? ""} - ${cliente.bairro ?? ""}, ${cliente.cidade ?? ""}';
        }

        subtitle += '\nData: ${_dateFormat.format(lancamento.dtEmissao)}\nPagamento: ${lancamento.tipoPagamento ?? "Não informado"}';

        return BluetoothPrinterService.instance.printReceipt(
          title: 'RECIBO',
          subtitle: subtitle,
          items: items,
          total: _currencyFormat.format(totalRecibo),
          footer: 'Obrigado pela preferencia!\n\n--------------------------------\n      Assinatura',
        );
      },
    );

    if (success) {
      _showReprintDialog(lancamento, () => _printBluetoothLancamento(lancamento));
    }
    } catch (e) {
      _showSnackBar('Erro ao imprimir via Bluetooth: $e', isError: true);
    }
  }

  Future<void> _printMinimalistLancamento(LancamentoCabecalho lancamento) async {
    try {
      // Fetch items for printing
    final itemsResponse = await SupabaseService.client
        .from('lancto_itens')
        .select('*, produtos(nome)')
        .eq('cabecalho_id', lancamento.id!);

    final printItens = (itemsResponse as List).map((e) => LancamentoItem.fromJson(e)).toList();
    
    // Fetch full customer details
    final clienteResponse = await SupabaseService.client
        .from('clientes')
        .select()
        .eq('id', lancamento.clienteId)
        .single();
    final cliente = Cliente.fromJson(clienteResponse);

    final totalQtd = printItens.fold<int>(0, (sum, item) => sum + item.quantidade);

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 10,
          marginRight: 2,
          marginTop: 10,
          marginBottom: 10,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'RESUMO DE ENTREGA',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Divider(),
              pw.Text('Cliente: ${lancamento.clienteNome ?? ""}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (cliente.cnpjCpf != null && cliente.cnpjCpf!.isNotEmpty)
                pw.Text('CNPJ/CPF: ${cliente.cnpjCpf}', style: const pw.TextStyle(fontSize: 9)),
              if (cliente.logradouro != null && cliente.logradouro!.isNotEmpty)
                pw.Text('Endereço: ${cliente.logradouro}, ${cliente.numero ?? ""} - ${cliente.bairro ?? ""}, ${cliente.cidade ?? ""}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('Data: ${_dateFormat.format(lancamento.dtEmissao)}'),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('QUANTIDADE TOTAL:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('$totalQtd', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.Center(child: pw.Text('Documento simplificado', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic))),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    _showReprintDialog(lancamento, () => _printMinimalistLancamento(lancamento));
    } catch (e) {
      _showSnackBar('Erro ao gerar resumo (PDF): $e', isError: true);
    }
  }


  void _showReprintDialog(LancamentoCabecalho lancamento, Future<void> Function() printAction) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.print_outlined,
                  color: Color(0xFF3B82F6),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Impressão Concluída',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Deseja imprimir novamente?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (isAdding) {
                          setState(() {
                            isAdding = false;
                            _clearForm();
                          });
                        } else {
                          // Se já estiver na tabela, tenta voltar para o Dashboard se possível
                          // Como LancamentosPage não controla o HomePage, vamos apenas fechar o dialog.
                          // Se quisermos forçar a ida pro Dashboard, precisaríamos de um callback.
                          // Mas "voltar a tela anterior" costuma significar sair da tela atual.
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Não',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        printAction();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Sim',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Card(
          margin: EdgeInsets.all(isMobile ? 8 : 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flex(
                  direction: isMobile ? Axis.vertical : Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Text(
                      isAdding ? (_editingId != null ? 'Editando Lançamento' : 'Novo Lançamento') : 'Lançamentos de Venda',
                      style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold),
                    ),
                    if (!isAdding)
                      Padding(
                        padding: EdgeInsets.only(top: isMobile ? 12 : 0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _clearForm();
                            setState(() => isAdding = true);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Novo Lançamento'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                if (isAdding)
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

    final filteredClientes = clientes
        .where((c) => c.razaoSocial.toLowerCase().contains(_clienteSearch.toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabeçalho
        isMobile 
          ? Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildClienteField(isMobile, filteredClientes),
                _buildDateField(isMobile),
                _buildTipoPagamentoField(isMobile),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildClienteField(isMobile, filteredClientes)),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _buildDateField(isMobile)),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _buildTipoPagamentoField(isMobile)),
              ],
            ),

        const SizedBox(height: 24),

        // Itens da Venda
        Container(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Itens da Venda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
              ),
              const SizedBox(height: 16),
              
              if (!isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linha 1: Produto e Quantidade
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedProdutoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Produto',
                              border: OutlineInputBorder(),
                            ),
                            items: produtos.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.nome, overflow: TextOverflow.ellipsis),
                            )).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                final p = produtos.firstWhere((prod) => prod.id == value);
                                setState(() {
                                  _selectedProdutoId = value;
                                  _updateItemPrices(p);
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: '1',
                            decoration: const InputDecoration(
                              labelText: 'Qtd',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => _itemQtd = int.tryParse(v) ?? 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Linha 2: Valores e Botão
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Venda (Uni)',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Color(0xFFF1F5F9),
                            ),
                            readOnly: true,
                            controller: TextEditingController(text: _currencyFormat.format(_itemVrVenda)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Desconto (Uni)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              final cleanValue = v.replaceAll(RegExp(r'[^\d,]'), '').replaceAll(',', '.');
                              _itemVrDesconto = double.tryParse(cleanValue) ?? 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Adicionar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedProdutoId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Produto',
                        border: OutlineInputBorder(),
                      ),
                      items: produtos.map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.nome, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          final p = produtos.firstWhere((prod) => prod.id == value);
                          setState(() {
                            _selectedProdutoId = value;
                            _updateItemPrices(p);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: '1',
                            decoration: const InputDecoration(
                              labelText: 'Qtd',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => _itemQtd = int.tryParse(v) ?? 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Venda (Uni)',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Color(0xFFF1F5F9),
                            ),
                            readOnly: true,
                            controller: TextEditingController(text: _currencyFormat.format(_itemVrVenda)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Desconto (Uni)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final cleanValue = v.replaceAll(RegExp(r'[^\d,]'), '').replaceAll(',', '.');
                        _itemVrDesconto = double.tryParse(cleanValue) ?? 0;
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Tabela de itens
              if (itens.isNotEmpty)
                Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: isMobile ? 20 : 40,
                      columns: const [
                        DataColumn(label: Text('Produto')),
                        DataColumn(label: Text('Custo')),
                        DataColumn(label: Text('Venda')),
                        DataColumn(label: Text('Desc.')),
                        DataColumn(label: Text('Total')),
                        DataColumn(label: Text('Ações')),
                      ],
                      rows: itens.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return DataRow(cells: [
                          DataCell(Text('${item.produtoNome} (x${item.quantidade})')),
                          DataCell(Text(_currencyFormat.format(item.custoTotal))),
                          DataCell(Text(_currencyFormat.format(item.vrVenda * item.quantidade))),
                          DataCell(Text(_currencyFormat.format(item.vrDesconto * item.quantidade))),
                          DataCell(Text(_currencyFormat.format(item.subtotal))),
                          DataCell(IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => _removeItem(index),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Totais
        Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          mainAxisAlignment: isMobile ? MainAxisAlignment.start : MainAxisAlignment.end,
          crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                const Text('Total Venda', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(_currencyFormat.format(_totalVenda), style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(width: isMobile ? 0 : 32, height: isMobile ? 12 : 0),
            Column(
              crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                const Text('Lucro Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(_currencyFormat.format(_totalLucro), style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold, color: const Color(0xFF22C55E))),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Botões
        Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              flex: isMobile ? 0 : 1,
              child: SizedBox(
                width: isMobile ? double.infinity : null,
                child: ElevatedButton.icon(
                  onPressed: _saveLancamento,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(_editingId != null ? 'Salvar Alterações' : 'Finalizar Lançamento'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 12 : 0),
            Expanded(
              flex: isMobile ? 0 : 1,
              child: SizedBox(
                width: isMobile ? double.infinity : null,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _clearForm();
                    setState(() => isAdding = false);
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
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTable() {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 60,
          dataRowMaxHeight: 60,
          headingRowHeight: 60,
          columnSpacing: 100,
          columns: const [
            DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Pagamento', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total Venda', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Lucro', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: lancamentos.map((l) {
            return DataRow(cells: [
              DataCell(Text(_dateFormat.format(l.dtEmissao))),
              DataCell(Text(l.clienteNome ?? '')),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (l.tipoPagamento == 'A Prazo' ? Colors.orange : Colors.blue).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (l.tipoPagamento == 'A Prazo' ? Colors.orange : Colors.blue).withOpacity(0.2),
                  ),
                ),
                child: Text(
                  l.tipoPagamento ?? 'A Vista',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: l.tipoPagamento == 'A Prazo' ? Colors.orange.shade800 : Colors.blue.shade800,
                  ),
                ),
              )),
              DataCell(Text(_currencyFormat.format(l.vrTotalVenda))),
              DataCell(Text(
                _currencyFormat.format(l.vrTotalLucro),
                style: const TextStyle(color: Color(0xFF4ADE80)),
              )),
              DataCell(PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF94A3B8)),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _editLancamento(l);
                      break;
                    case 'print_pdf':
                      _printLancamento(l);
                      break;
                    case 'print_min_pdf':
                      _printMinimalistLancamento(l);
                      break;
                    case 'print_bt':
                      _printBluetoothLancamento(l);
                      break;
                    case 'delete':
                      _deleteLancamento(l.id!);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Color(0xFF94A3B8), size: 20),
                        SizedBox(width: 12),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'print_pdf',
                    child: Row(
                      children: [
                        Icon(Icons.print, color: Color(0xFF94A3B8), size: 20),
                        SizedBox(width: 12),
                        Text('Imprimir PDF'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'print_min_pdf',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, color: Color(0xFF64748B), size: 20),
                        SizedBox(width: 12),
                        Text('Resumo (Cliente/Qtd)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'print_bt',
                    child: Row(
                      children: [
                        Icon(Icons.bluetooth, color: Color(0xFF3B82F6), size: 20),
                        SizedBox(width: 12),
                        Text('Imprimir Bluetooth'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Color(0xFFEF4444), size: 20),
                        SizedBox(width: 12),
                        Text('Excluir', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildClienteField(bool isMobile, List<Cliente> filteredClientes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cliente', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Buscar cliente...',
            border: OutlineInputBorder(),
          ),
          controller: _clienteSearchController,
          onChanged: (value) {
            setState(() {
              _clienteSearch = value;
              _showClienteDropdown = true;
            });
          },
          onTap: () => setState(() => _showClienteDropdown = true),
        ),
        if (_showClienteDropdown && filteredClientes.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filteredClientes.length,
              itemBuilder: (context, index) {
                final cliente = filteredClientes[index];
                return ListTile(
                  title: Text(cliente.razaoSocial),
                  onTap: () {
                    setState(() {
                      _selectedClienteId = cliente.id;
                      _clienteSearch = cliente.razaoSocial;
                      _clienteSearchController.text = _clienteSearch;
                      _showClienteDropdown = false;
                      // Atualiza os preços se já houver um produto selecionado
                      if (_selectedProdutoId != null) {
                        final p = produtos.firstWhere((prod) => prod.id == _selectedProdutoId);
                        _updateItemPrices(p);
                      }
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDateField(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Data de Emissão', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _dtEmissao,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) setState(() => _dtEmissao = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_dateFormat.format(_dtEmissao)),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTipoPagamentoField(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tipo de Pagamento', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: _tipoPagamento,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(),
          ),
          items: ['A Vista', 'A Prazo'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _tipoPagamento = value);
          },
        ),
      ],
    );
  }
}
