import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/supabase_service.dart';
import '../services/bluetooth_printer_service.dart';

class RelatorioPage extends StatefulWidget {
  const RelatorioPage({super.key});

  @override
  State<RelatorioPage> createState() => _RelatorioPageState();
}

enum ReportRange { diario, semanal, mensal }
enum ReportView { lista, completo, despesas }

class _RelatorioPageState extends State<RelatorioPage> {
  List<Map<String, dynamic>> reportItems = [];
  List<Map<String, dynamic>> expenseItems = [];
  bool isLoading = false;
  DateTime _selectedDate = DateTime.now();
  ReportRange _selectedRange = ReportRange.diario;
  ReportView _selectedView = ReportView.completo;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  dynamic _getSingle(dynamic value) {
    if (value is List && value.isNotEmpty) return value[0];
    if (value is Map) return value;
    return null;
  }

  bool _isClienteGeloDoPorto(Map<String, dynamic> item) {
    final cabecalho = _getSingle(item['lancto_cabecalho']);
    final cliente = _getSingle(cabecalho?['clientes']);
    return cliente?['is_gelo_do_porto'] == true;
  }

  double _getClienteGeloDoPortoValor(Map<String, dynamic> item) {
    final cabecalho = _getSingle(item['lancto_cabecalho']);
    final cliente = _getSingle(cabecalho?['clientes']);
    return double.tryParse(cliente?['valor_gelo_do_porto']?.toString() ?? '0') ?? 0;
  }

  double _getItemBaseVenda(Map<String, dynamic> item) {
    final vrVenda = double.tryParse(item['vr_venda']?.toString() ?? '0') ?? 0;
    final valorGeloDoPorto = _getClienteGeloDoPortoValor(item);
    if (_isClienteGeloDoPorto(item) && valorGeloDoPorto > 0) {
      return valorGeloDoPorto;
    }
    return vrVenda;
  }

  double _getItemDesconto(Map<String, dynamic> item) {
    return double.tryParse(item['vr_desconto']?.toString() ?? '0') ?? 0;
  }

  double _getItemUnitVenda(Map<String, dynamic> item) {
    final baseVenda = _getItemBaseVenda(item);
    final desconto = _getItemDesconto(item);
    return (baseVenda - desconto) < 0 ? 0 : baseVenda - desconto;
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      DateTime startDate;
      DateTime endDate;

      switch (_selectedRange) {
        case ReportRange.diario:
          startDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          endDate = startDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
          break;
        case ReportRange.semanal:
          // Início da semana (Domingo)
          startDate = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
          startDate = DateTime(startDate.year, startDate.month, startDate.day);
          endDate = startDate.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
          break;
        case ReportRange.mensal:
          startDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
          endDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1).subtract(const Duration(milliseconds: 1));
          break;
      }

      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];
      
      var query = SupabaseService.client
          .from('lancto_itens')
          .select('*, produtos(nome), lancto_cabecalho!inner(id, dt_emissao, is_excluido, vr_total_venda, vr_total_custo, vr_total_lucro, clientes(razao_social, is_gelo_do_porto, valor_gelo_do_porto))')
          .eq('lancto_cabecalho.is_excluido', false);

      if (_selectedRange == ReportRange.diario) {
        query = query.eq('lancto_cabecalho.dt_emissao', startStr);
      } else {
        query = query.gte('lancto_cabecalho.dt_emissao', startStr)
                     .lte('lancto_cabecalho.dt_emissao', endStr);
      }

      final response = await query.order('id', ascending: false);

      // Fetch expenses for the same period
      final expenseResponse = await SupabaseService.client
          .from('despesas')
          .select()
          .eq('is_excluido', false)
          .gte('data', startStr)
          .lte('data', endStr)
          .order('data', ascending: true);

      if (mounted) {
        setState(() {
          reportItems = List<Map<String, dynamic>>.from(response);
          expenseItems = List<Map<String, dynamic>>.from(expenseResponse);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  double get _totalVendas {
    return reportItems.fold(0.0, (sum, item) {
      final unitVenda = _getItemUnitVenda(item);
      final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
      return sum + (unitVenda * qtd);
    });
  }

  double get _totalCusto {
    return reportItems.fold(0.0, (sum, item) {
      final vrCusto = double.tryParse(item['vr_custo']?.toString() ?? '0') ?? 0;
      final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
      return sum + (vrCusto * qtd);
    });
  }

  double get _totalLucro => _totalVendas - _totalCusto - _totalExpenses;

  int get _totalQuantidade {
    return reportItems.fold(0, (sum, item) {
      return sum + (int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1);
    });
  }

  double get _totalExpenses {
    return expenseItems.fold(0.0, (sum, item) => sum + (double.tryParse(item['valor']?.toString() ?? '0') ?? 0));
  }

  int get _quantidadeVendas {
    final ids = reportItems.map((item) {
      final cabecalho = _getSingle(item['lancto_cabecalho']);
      return cabecalho?['id'];
    }).where((id) => id != null).toSet();
    return ids.length;
  }

  final _scrollController = ScrollController();

  Future<void> _printReport() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gerando PDF para impressão...'), duration: Duration(seconds: 2)),
      );

      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final pdf = pw.Document();

      // Agrupamento para os totais por produto
      final Map<String, Map<String, dynamic>> productTotals = {};
      
      for (var item in reportItems) {
        final produtos = _getSingle(item['produtos']);
        final nomeProduto = produtos?['nome'] ?? 'N/A';
        
        final unitVenda = _getItemUnitVenda(item);
        final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
        final totalItem = unitVenda * qtd;

        if (productTotals.containsKey(nomeProduto)) {
          productTotals[nomeProduto]!['qtd'] += qtd;
          productTotals[nomeProduto]!['total'] += totalItem;
        } else {
          productTotals[nomeProduto] = {
            'qtd': qtd,
            'total': totalItem,
          };
        }
      }

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
          ),
          pageFormat: PdfPageFormat.roll80.copyWith(
            height: 1000 * PdfPageFormat.mm,
            marginLeft: 5 * PdfPageFormat.mm,
            marginRight: 10 * PdfPageFormat.mm,
            marginTop: 5 * PdfPageFormat.mm,
            marginBottom: 5 * PdfPageFormat.mm,
          ),
          build: (context) => [
            pw.Center(child: pw.Text('RELATÓRIO DE VENDAS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('Período: ${_getRangeLabel()}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 1.0),
            
            // Lista detalhada (Sem nome da pessoa, em uma linha) - Ordenada Alfabeticamente
            ...(() {
              final sortedItems = List<Map<String, dynamic>>.from(reportItems);
              sortedItems.sort((a, b) {
                final prodA = _getSingle(a['produtos'])?['nome']?.toString().toLowerCase() ?? '';
                final prodB = _getSingle(b['produtos'])?['nome']?.toString().toLowerCase() ?? '';
                return prodA.compareTo(prodB);
              });
              
              return sortedItems.map((item) {
                final produtos = _getSingle(item['produtos']);
                final produto = produtos?['nome'] ?? 'N/A';
                
                final unitVenda = _getItemUnitVenda(item);
                final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
                final total = unitVenda * qtd;

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(produto, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(qtd.toString(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(_currencyFormat.format(total), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                );
              });
            })(),
            
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1.0),
            pw.SizedBox(height: 2),
            pw.Text('TOTAIS:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),

            ...(() {
              final sortedEntries = productTotals.entries.toList()
                ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
              
              return sortedEntries.map((entry) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(entry.key, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(entry.value['qtd'].toString(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(_currencyFormat.format(entry.value['total']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                );
              });
            })(),

            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Total de Quantidades: $_totalQuantidade', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Total Vendas: ${_currencyFormat.format(_totalVendas)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Total Custo: ${_currencyFormat.format(_totalCusto)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Total Despesas: ${_currencyFormat.format(_totalExpenses)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Lucro Total: ${_currencyFormat.format(_totalLucro)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Relatorio_Vendas_${_getRangeLabel().replaceAll(' ', '_')}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printFullReport() async {
    if (reportItems.isEmpty) return;
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      
      // Agrupamento por venda (cabecalho)
      final Map<String, Map<String, dynamic>> salesSummary = {};
      
      for (var item in reportItems) {
        final cabecalho = _getSingle(item['lancto_cabecalho']);
        final saleId = cabecalho?['id']?.toString() ?? 'N/A';
        final cliente = _getSingle(cabecalho?['clientes']);
        final nomeCliente = cliente?['razao_social'] ?? 'N/A';
        
        final vrCusto = double.tryParse(item['vr_custo']?.toString() ?? '0') ?? 0;
        final baseVenda = _getItemBaseVenda(item);
        final vrDesconto = _getItemDesconto(item);
        final unitVenda = _getItemUnitVenda(item);
        final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;

        final dtEmissao = cabecalho?['dt_emissao']?.toString() ?? '';
        final dia = dtEmissao.isNotEmpty ? DateTime.tryParse(dtEmissao)?.day.toString() ?? '' : '';

        if (salesSummary.containsKey(saleId)) {
          salesSummary[saleId]!['qtd'] += qtd;
          salesSummary[saleId]!['custo'] += (vrCusto * qtd);
          salesSummary[saleId]!['venda'] += (baseVenda * qtd);
          salesSummary[saleId]!['desconto'] += (vrDesconto * qtd);
          salesSummary[saleId]!['total'] += (unitVenda * qtd);
        } else {
          salesSummary[saleId] = {
            'dia': dia,
            'data': dtEmissao, // Store full date for accurate sorting
            'cliente': nomeCliente,
            'qtd': qtd,
            'custo': (vrCusto * qtd),
            'venda': (baseVenda * qtd),
            'desconto': (vrDesconto * qtd),
            'total': (unitVenda * qtd),
          };
        }
      }

      final sortedSales = salesSummary.values.toList()
        ..sort((a, b) => (a['data'] ?? '').compareTo(b['data'] ?? ''));

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
          ),
          pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: 10 * PdfPageFormat.mm,
            marginRight: 10 * PdfPageFormat.mm,
            marginTop: 10 * PdfPageFormat.mm,
            marginBottom: 10 * PdfPageFormat.mm,
          ),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('RELATÓRIO COMPLETO', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Período: ${_getRangeLabel()}', style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5), // Dia
                1: const pw.FlexColumnWidth(3), // Cliente
                2: const pw.FlexColumnWidth(1), // Qtd
                3: const pw.FlexColumnWidth(1.5), // Custo
                4: const pw.FlexColumnWidth(1.5), // Venda
                5: const pw.FlexColumnWidth(1.5), // Desconto
                6: const pw.FlexColumnWidth(1.5), // Total
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Dia', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Cliente', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Qtd', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Custo', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Venda', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Desc.', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  ],
                ),
                // Data rows
                ...sortedSales.map((sale) => pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(sale['dia'] ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(sale['cliente'], style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(sale['qtd'].toString(), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format(sale['custo']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format(sale['venda']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format(sale['desconto']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format(sale['total']), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
                  ],
                )).toList(),
              ],
            ),
            
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Resumo Geral:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text('Total de Quantidades: $_totalQuantidade', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('Total Vendas: ${_currencyFormat.format(_totalVendas)}', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('Total Custo: ${_currencyFormat.format(_totalCusto)}', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('Total Despesas: ${_currencyFormat.format(_totalExpenses)}', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('Total Lucro: ${_currencyFormat.format(_totalLucro)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.green)),
                ],
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Relatorio_Completo_${_getRangeLabel().replaceAll(' ', '_')}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir relatório completo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getRangeLabel() {
    switch (_selectedRange) {
      case ReportRange.diario:
        return _dateFormat.format(_selectedDate);
      case ReportRange.semanal:
        final start = _selectedDate.subtract(Duration(days: _selectedDate.weekday % 7));
        final end = start.add(const Duration(days: 6));
        return '${_dateFormat.format(start)} a ${_dateFormat.format(end)}';
      case ReportRange.mensal:
        return DateFormat('MMMM/yyyy', 'pt_BR').format(_selectedDate);
    }
  }

  Future<void> _printSummaryReport() async {
    if (reportItems.isEmpty) return;
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      
      // Grouping by sale
      final Map<String, List<dynamic>> salesMap = {};
      for (var item in reportItems) {
        final cabecalho = _getSingle(item['lancto_cabecalho']);
        final saleId = cabecalho?['id']?.toString() ?? 'N/A';
        salesMap.putIfAbsent(saleId, () => []).add(item);
      }

      // Aggregate totals
      final Map<String, int> productTotals = {};
      for (var item in reportItems) {
        final produtos = _getSingle(item['produtos']);
        final nomeProduto = produtos?['nome'] ?? 'N/A';
        final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
        productTotals[nomeProduto] = (productTotals[nomeProduto] ?? 0) + qtd;
      }

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
          ),
          pageFormat: PdfPageFormat.roll80.copyWith(
            height: 1000 * PdfPageFormat.mm,
            marginLeft: 5 * PdfPageFormat.mm,
            marginRight: 10 * PdfPageFormat.mm,
            marginTop: 5 * PdfPageFormat.mm,
            marginBottom: 5 * PdfPageFormat.mm,
          ),
          build: (context) => [
            pw.Center(child: pw.Text('RESUMO DE VENDAS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('Data: ${_dateFormat.format(_selectedDate)}', style: pw.TextStyle(fontSize: 8))),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 1.0),
            
            // Aggregated section
            pw.Text('TOTAIS POR PRODUTO:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...productTotals.entries.map((entry) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(entry.key, style: pw.TextStyle(fontSize: 8)),
                pw.Text(entry.value.toString(), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ],
            )).toList(),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 1.0),
            pw.SizedBox(height: 5),
            
            // Detailed section
            pw.Text('LISTA DE VENDAS:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            ...salesMap.entries.map((saleEntry) {
              final items = saleEntry.value;
              final cabecalho = _getSingle(items.first['lancto_cabecalho']);
              final cliente = _getSingle(cabecalho['clientes']);
              final nomeCliente = cliente?['razao_social'] ?? 'N/A';
              
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(nomeCliente, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  ...items.map((item) {
                    final produtos = _getSingle(item['produtos']);
                    final nomeProduto = produtos?['nome'] ?? 'N/A';
                    final qtd = item['quantidade'] ?? 0;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 6),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('- $nomeProduto', style: pw.TextStyle(fontSize: 7)),
                          pw.Text('$qtd', style: pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                    );
                  }).toList(),
                  pw.SizedBox(height: 4),
                ],
              );
            }).toList(),
            
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Text('*** FIM DO RESUMO ***', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic))),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Resumo_Vendas_${_dateFormat.format(_selectedDate).replaceAll('/', '_')}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir resumo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printBluetoothFullReport() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impressão Bluetooth não é suportada no navegador. Use PDF.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (reportItems.isEmpty) return;

    // Agrupamento por venda (cabecalho)
    final Map<String, Map<String, dynamic>> salesSummary = {};
    for (var item in reportItems) {
      final cabecalho = _getSingle(item['lancto_cabecalho']);
      final saleId = cabecalho?['id']?.toString() ?? 'N/A';
      final cliente = _getSingle(cabecalho?['clientes']);
      final nomeCliente = cliente?['razao_social'] ?? 'N/A';
      
      final unitVenda = _getItemUnitVenda(item);
      final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;

      final dtEmissao = cabecalho?['dt_emissao']?.toString() ?? '';
      final dia = dtEmissao.isNotEmpty ? DateTime.tryParse(dtEmissao)?.day.toString() ?? '' : '';

      if (salesSummary.containsKey(saleId)) {
        salesSummary[saleId]!['qtd'] += qtd;
        salesSummary[saleId]!['total'] += (unitVenda * qtd);
      } else {
        salesSummary[saleId] = {
          'dia': dia,
          'data': dtEmissao,
          'cliente': nomeCliente,
          'qtd': qtd,
          'total': (unitVenda * qtd),
        };
      }
    }

    final sortedSales = salesSummary.values.toList()
      ..sort((a, b) => (a['data'] ?? '').compareTo(b['data'] ?? ''));

    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        final List<Map<String, String>> btItems = [];
        
        for (var sale in sortedSales) {
          final diaPrefix = sale['dia'] != null && sale['dia'] != '' ? 'D:${sale['dia']} - ' : '';
          btItems.add({
            'name': '$diaPrefix${sale['cliente']}',
            'qty': '${sale['qtd']}',
            'price': _currencyFormat.format(sale['total']),
          });
        }

        final totals = {
          'Total Quantidades': '$_totalQuantidade',
          'Total Vendas': _currencyFormat.format(_totalVendas),
          'Total Custo': _currencyFormat.format(_totalCusto),
          'Total Despesas': _currencyFormat.format(_totalExpenses),
          'Lucro Total': _currencyFormat.format(_totalLucro),
        };

        return BluetoothPrinterService.instance.printReport(
          title: 'RELATORIO COMPLETO',
          date: _getRangeLabel(),
          items: btItems,
          totals: totals,
        );
      },
    );

    if (success == true && mounted) {
      _showReprintDialog(onReprint: _printBluetoothFullReport);
    }
  }

  Future<void> _printBluetoothSummaryReport() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impressão Bluetooth não é suportada no navegador. Use PDF.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (reportItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum dado para imprimir'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Grouping for BT
    final Map<String, List<dynamic>> salesMap = {};
    for (var item in reportItems) {
      final cabecalho = _getSingle(item['lancto_cabecalho']);
      final saleId = cabecalho?['id']?.toString() ?? 'N/A';
      salesMap.putIfAbsent(saleId, () => []).add(item);
    }

    // Totals for BT
    final Map<String, int> productTotals = {};
    for (var item in reportItems) {
      final produtos = _getSingle(item['produtos']);
      final nomeProduto = produtos?['nome'] ?? 'N/A';
      final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
      productTotals[nomeProduto] = (productTotals[nomeProduto] ?? 0) + qtd;
    }

    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        final List<Map<String, String>> btItems = [];
        
        // Add totals first
        btItems.add({'name': 'TOTAIS POR PRODUTO:', 'qty': '', 'price': ''});
        for (var entry in productTotals.entries) {
          btItems.add({'name': entry.key, 'qty': '${entry.value}', 'price': ''});
        }
        btItems.add({'name': '--------------------------------', 'qty': '', 'price': ''});
        btItems.add({'name': 'LISTA DE VENDAS:', 'qty': '', 'price': ''});
        
        // Add detailed sales
        for (var saleEntry in salesMap.entries) {
          final items = saleEntry.value;
          final cabecalho = _getSingle(items.first['lancto_cabecalho']);
          final cliente = _getSingle(cabecalho['clientes']);
          final nomeCliente = (cliente?['razao_social'] ?? 'N/A');
          
          btItems.add({'name': nomeCliente, 'qty': '', 'price': ''});
          for (var item in items) {
            final produtos = _getSingle(item['produtos']);
            final nomeProduto = produtos?['nome'] ?? 'N/A';
            final qtd = item['quantidade'] ?? 0;
            btItems.add({'name': '  $nomeProduto', 'qty': '$qtd', 'price': ''});
          }
        }

        return BluetoothPrinterService.instance.printReport(
          title: 'RESUMO DE VENDAS',
          date: _dateFormat.format(_selectedDate),
          items: btItems,
          totals: {}, 
        );
      },
    );

    if (success == true && mounted) {
      _showReprintDialog(onReprint: _printBluetoothSummaryReport);
    }
  }

  Future<void> _printBluetoothReport() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impressão Bluetooth não é suportada no navegador. Use PDF.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (reportItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum dado para imprimir'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Agrupamento para os totais por produto
    final Map<String, Map<String, dynamic>> productTotals = {};
    
    for (var item in reportItems) {
      final produtos = _getSingle(item['produtos']);
      final nomeProduto = produtos?['nome'] ?? 'N/A';
      
      final unitVenda = _getItemUnitVenda(item);
      final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
      final totalItem = unitVenda * qtd;

      if (productTotals.containsKey(nomeProduto)) {
        productTotals[nomeProduto]!['qtd'] += qtd;
        productTotals[nomeProduto]!['total'] += totalItem;
      } else {
        productTotals[nomeProduto] = {
          'qtd': qtd,
          'total': totalItem,
        };
      }
    }

    // Ordenar alfabeticamente
    final sortedEntries = productTotals.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        final items = sortedEntries.map((entry) => {
          'name': entry.key,
          'qty': '${entry.value['qtd']}',
          'price': _currencyFormat.format(entry.value['total']),
        }).toList();

        final totals = {
          'Total Quantidades': '$_totalQuantidade',
          'Total Vendas': _currencyFormat.format(_totalVendas),
          'Total Custo': _currencyFormat.format(_totalCusto),
          'Total Despesas': _currencyFormat.format(_totalExpenses),
          'Lucro Total': _currencyFormat.format(_totalLucro),
        };

        return BluetoothPrinterService.instance.printReport(
          title: 'RELATÓRIO',
          date: _dateFormat.format(_selectedDate),
          items: items,
          totals: totals,
        );
      },
    );

    if (success == true && mounted) {
      _showReprintDialog(onReprint: _printBluetoothReport);
    }
  }

  Future<void> _printExpensesPdf() async {
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
          header: (context) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('RELATÓRIO DE DESPESAS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Período: ${_getRangeLabel()}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Divider(),
            ],
          ),
          build: (context) => [
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5), // Dia
                1: const pw.FlexColumnWidth(3), // Beneficiário
                2: const pw.FlexColumnWidth(2), // Referente
                3: const pw.FlexColumnWidth(1.5), // Valor
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Dia', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Beneficiário', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Referente', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Valor', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                  ],
                ),
                ...expenseItems.map((e) {
                  final data = DateTime.tryParse(e['data']?.toString() ?? '') ?? DateTime.now();
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(data.day.toString(), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e['beneficiario'] ?? '', style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(e['referente'] ?? '', style: const pw.TextStyle(fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format(e['valor'] ?? 0), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9))),
                    ],
                  );
                }).toList(),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'TOTAL DAS DESPESAS: ${_currencyFormat.format(_totalExpenses)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e')));
    }
  }

  Future<void> _printExpensesBluetooth() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impressão Bluetooth não é suportada no navegador. Use PDF.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (expenseItems.isEmpty) return;

    final success = await BluetoothPrinterService.connectAndPrint(
      context,
      printFunction: () async {
        final items = expenseItems.map((e) {
          final data = DateTime.tryParse(e['data']?.toString() ?? '') ?? DateTime.now();
          return {
            'dia': data.day.toString(),
            'beneficiary': e['beneficiario']?.toString() ?? '',
            'value': _currencyFormat.format(e['valor'] ?? 0),
          };
        }).toList();

        return BluetoothPrinterService.instance.printExpenses(
          items: items,
          total: _currencyFormat.format(_totalExpenses),
          period: _getRangeLabel(),
        );
      },
    );

    if (success && mounted) {
      _showReprintDialog(onReprint: _printExpensesBluetooth);
    }
  }

  void _showReprintDialog({VoidCallback? onReprint}) {
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
                      onPressed: () => Navigator.of(context).pop(),
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
                        if (onReprint != null) {
                          onReprint();
                        } else {
                          _printBluetoothReport();
                        }
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
              mainAxisSize: MainAxisSize.min, // Use min to avoid stretching in Column
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Relatório',
                      style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold),
                    ),
                    
                    if (!isLoading && reportItems.isNotEmpty)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'full_pdf': _printFullReport(); break;
                            case 'pdf': _printReport(); break;
                            case 'full_bt': _printBluetoothFullReport(); break;
                            case 'bluetooth': _printBluetoothReport(); break;
                            case 'expenses_pdf': _printExpensesPdf(); break;
                            case 'expenses_bt': _printExpensesBluetooth(); break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'full_pdf',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf, color: Color(0xFF4F46E5), size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Completo (PDF)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'pdf',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf, color: Colors.blueAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Itens (PDF)'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'full_bt',
                            child: Row(
                              children: [
                                Icon(Icons.bluetooth, color: Color(0xFF4F46E5), size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Completo (BT)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'bluetooth',
                            child: Row(
                              children: [
                                Icon(Icons.bluetooth_audio, color: Colors.blueAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Itens (BT)'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'expenses_pdf',
                            child: Row(
                              children: [
                                Icon(Icons.money_off, color: Colors.redAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Despesas (PDF)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'expenses_bt',
                            child: Row(
                              children: [
                                Icon(Icons.bluetooth_searching, color: Colors.orangeAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Imprimir Despesas (BT)'),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.print_outlined, color: Color(0xFF475569), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'IMPRIMIR RELATÓRIOS',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.keyboard_arrow_down, color: Color(0xFF475569), size: 18),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Filtros
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    if (!isLoading && reportItems.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Configurações do Relatório', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              SegmentedButton<ReportRange>(
                                segments: const [
                                  ButtonSegment(value: ReportRange.diario, label: Text('Dia'), icon: Icon(Icons.today, size: 16)),
                                  ButtonSegment(value: ReportRange.semanal, label: Text('Semana'), icon: Icon(Icons.view_week, size: 16)),
                                  ButtonSegment(value: ReportRange.mensal, label: Text('Mês'), icon: Icon(Icons.calendar_month, size: 16)),
                                ],
                                selected: {_selectedRange},
                                onSelectionChanged: (Set<ReportRange> newSelection) {
                                  setState(() {
                                    _selectedRange = newSelection.first;
                                  });
                                  _fetchData();
                                },
                                style: SegmentedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  selectedBackgroundColor: const Color(0xFF4F46E5).withOpacity(0.1),
                                  selectedForegroundColor: const Color(0xFF4F46E5),
                                ),
                              ),

                            ],
                          ),
                        ],
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Data de Referência', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                              _fetchData();
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_dateFormat.format(_selectedDate)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    if (!isLoading && reportItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.2)),
                        ),
                        child: Text(
                          _selectedView == ReportView.despesas 
                            ? '${expenseItems.length} despesas no período'
                            : '$_quantidadeVendas vendas no período',
                          style: const TextStyle(
                            color: Color(0xFF4F46E5),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
                // Cards de Resumo
                if (!isLoading && reportItems.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                        _buildSummaryCard(
                          _selectedView == ReportView.despesas ? 'Total Despesas' : 'Total Vendas',
                          _selectedView == ReportView.despesas ? _totalExpenses : _totalVendas,
                          _selectedView == ReportView.despesas ? Icons.money_off : Icons.trending_up,
                          _selectedView == ReportView.despesas ? Colors.red : const Color(0xFF4F46E5),
                          isMobile,
                        ),
                        if (_selectedView != ReportView.despesas) ...[
                          _buildSummaryCard(
                            'Total Custo',
                            _totalCusto,
                            Icons.money_off,
                            Colors.orange,
                            isMobile,
                          ),
                          _buildSummaryCard(
                            'Total Despesas',
                            _totalExpenses,
                            Icons.receipt_long,
                            Colors.red,
                            isMobile,
                          ),
                          _buildSummaryCard(
                            'Lucro Total',
                            _totalLucro,
                            Icons.payments,
                            Colors.green,
                            isMobile,
                          ),
                        ],
                      ],
                    ),
                  ],
                const SizedBox(height: 24),

                // Tabela
                if (isLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ))
                else if (reportItems.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('Nenhum lançamento encontrado para a data selecionada.'),
                  ))
                else if (_selectedView == ReportView.lista)
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: isMobile ? 20 : 40,
                        columns: const [
                          DataColumn(label: Text('Nome da Pessoa')),
                          DataColumn(label: Text('Produto')),
                          DataColumn(label: Text('Qtd')),
                          DataColumn(label: Text('Valor Venda')),
                          DataColumn(label: Text('Desc.')),
                          DataColumn(label: Text('Subtotal')),
                        ],
                        rows: reportItems.map((item) {
                          final cabecalho = _getSingle(item['lancto_cabecalho']);
                          final cliente = _getSingle(cabecalho?['clientes']);
                          final produtos = _getSingle(item['produtos']);
                          
                          final baseVenda = _getItemBaseVenda(item);
                          final vrDesconto = _getItemDesconto(item);
                          final unitVenda = _getItemUnitVenda(item);
                          final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;
                          final subtotal = unitVenda * qtd;

                          return DataRow(cells: [
                            DataCell(Text(cliente?['razao_social'] ?? 'N/A')),
                            DataCell(Text(produtos?['nome'] ?? 'N/A')),
                            DataCell(Text(qtd.toString())),
                            DataCell(Text(_currencyFormat.format(baseVenda))),
                            DataCell(Text(_currencyFormat.format(vrDesconto))),
                            DataCell(Text(_currencyFormat.format(subtotal))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  )
                else if (_selectedView == ReportView.completo)
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: isMobile ? 20 : 40,
                        columns: const [
                          DataColumn(label: Text('Dia')),
                          DataColumn(label: Text('Cliente')),
                          DataColumn(label: Text('Qtd Itens')),
                          DataColumn(label: Text('Custo Total')),
                          DataColumn(label: Text('Venda Total')),
                          DataColumn(label: Text('Total Desconto')),
                          DataColumn(label: Text('Total Final')),
                        ],
                        rows: () {
                          // Agrupamento por Cliente (Venda)
                          final Map<String, Map<String, dynamic>> salesSummary = {};
                          for (var item in reportItems) {
                            final cabecalho = _getSingle(item['lancto_cabecalho']);
                            final saleId = cabecalho?['id']?.toString() ?? 'N/A';
                            final cliente = _getSingle(cabecalho?['clientes']);
                            final nomeCliente = cliente?['razao_social'] ?? 'N/A';
                            
                            final vrCusto = double.tryParse(item['vr_custo']?.toString() ?? '0') ?? 0;
                            final baseVenda = _getItemBaseVenda(item);
                            final vrDesconto = _getItemDesconto(item);
                            final unitVenda = _getItemUnitVenda(item);
                            final qtd = int.tryParse(item['quantidade']?.toString() ?? '1') ?? 1;

                            final dtEmissao = cabecalho?['dt_emissao']?.toString() ?? '';
                            final dia = dtEmissao.isNotEmpty ? DateTime.tryParse(dtEmissao)?.day.toString() ?? '' : '';

                            if (salesSummary.containsKey(saleId)) {
                              salesSummary[saleId]!['qtd'] += qtd;
                              salesSummary[saleId]!['custo'] += (vrCusto * qtd);
                              salesSummary[saleId]!['venda'] += (baseVenda * qtd);
                              salesSummary[saleId]!['desconto'] += (vrDesconto * qtd);
                              salesSummary[saleId]!['total'] += (unitVenda * qtd);
                            } else {
                              salesSummary[saleId] = {
                                'dia': dia,
                                'data': dtEmissao,
                                'cliente': nomeCliente,
                                'qtd': qtd,
                                'custo': (vrCusto * qtd),
                                'venda': (baseVenda * qtd),
                                'desconto': (vrDesconto * qtd),
                                'total': (unitVenda * qtd),
                              };
                            }
                          }
                          
                          final sortedSales = salesSummary.values.toList()
                            ..sort((a, b) => (a['data'] ?? '').compareTo(b['data'] ?? ''));

                          return sortedSales.map((sale) => DataRow(cells: [
                            DataCell(Text(sale['dia'] ?? '')),
                            DataCell(Text(sale['cliente'])),
                            DataCell(Text(sale['qtd'].toString())),
                            DataCell(Text(_currencyFormat.format(sale['custo']))),
                            DataCell(Text(_currencyFormat.format(sale['venda']))),
                            DataCell(Text(_currencyFormat.format(sale['desconto']))),
                            DataCell(Text(_currencyFormat.format(sale['total']), style: const TextStyle(fontWeight: FontWeight.bold))),
                          ])).toList();
                        }(),
                    ),
                  ),
                )
                else
                  Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: isMobile ? 20 : 40,
                        columns: const [
                          DataColumn(label: Text('Dia')),
                          DataColumn(label: Text('Beneficiário')),
                          DataColumn(label: Text('Referente')),
                          DataColumn(label: Text('Valor')),
                        ],
                        rows: expenseItems.map((e) {
                          final data = DateTime.tryParse(e['data']?.toString() ?? '') ?? DateTime.now();
                          return DataRow(cells: [
                            DataCell(Text(data.day.toString())),
                            DataCell(Text(e['beneficiario'] ?? '')),
                            DataCell(Text(e['referente'] ?? '')),
                            DataCell(Text(_currencyFormat.format(e['valor'] ?? 0))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildSummaryCard(String title, double value, IconData icon, Color color, bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currencyFormat.format(value),
                  style: TextStyle(
                    fontSize: 18,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
