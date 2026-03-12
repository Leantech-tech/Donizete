import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/produto_model.dart';
import '../services/supabase_service.dart';

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({super.key});

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage> {
  List<Produto> produtos = [];
  bool isLoading = true;
  bool isEditing = false;
  
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _codigoController = TextEditingController();
  final _custoController = TextEditingController();
  final _margemController = TextEditingController();
  final _vendaController = TextEditingController(); // Added controller
  
  String? _editingId;
  bool _isAtivo = true;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _fetchProdutos();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _codigoController.dispose();
    _custoController.dispose();
    _margemController.dispose();
    _vendaController.dispose();
    super.dispose();
  }

  Future<void> _fetchProdutos() async {
    setState(() => isLoading = true);
    try {
      final response = await SupabaseService.client
          .from('produtos')
          .select()
          .eq('is_excluido', false)
          .order('created_at', ascending: false);
      
      setState(() {
        produtos = (response as List).map((e) => Produto.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Erro ao carregar produtos: $e', isError: true);
    }
  }

  void _clearForm() {
    _editingId = null;
    _isAtivo = true;
    _nomeController.clear();
    _codigoController.clear();
    _custoController.text = 'R\$ 0,00';
    _margemController.text = '0';
    _vendaController.text = 'R\$ 0,00';
  }

  double _parseCurrency(String value) {
    final cleanValue = value.replaceAll(RegExp(r'[^\d,]'), '').replaceAll(',', '.');
    return double.tryParse(cleanValue) ?? 0;
  }

  String _formatCurrency(double value) {
    return _currencyFormat.format(value);
  }

  void _calculateMargem() {
    final custo = _parseCurrency(_custoController.text);
    final venda = _parseCurrency(_vendaController.text);
    setState(() {
      final margem = Produto.calcularMargem(custo, venda);
      _margemController.text = margem.toStringAsFixed(2);
    });
  }

  void _calculateVenda() {
    final custo = _parseCurrency(_custoController.text);
    final margem = double.tryParse(_margemController.text) ?? 0;
    setState(() {
      final venda = Produto.calcularVenda(custo, margem);
      _vendaController.text = _formatCurrency(venda);
    });
  }

  void _editProduto(Produto produto) {
    _editingId = produto.id;
    _isAtivo = produto.isAtivo;
    _nomeController.text = produto.nome;
    _codigoController.text = produto.codigoInterno ?? '';
    _custoController.text = _formatCurrency(produto.vrCusto);
    _margemController.text = produto.margem.toString();
    _vendaController.text = _formatCurrency(produto.vrVenda);
    
    setState(() => isEditing = true);
  }

  Future<void> _saveProduto() async {
    if (!_formKey.currentState!.validate()) return;

    final produto = Produto(
      id: _editingId,
      nome: _nomeController.text,
      codigoInterno: _codigoController.text.isNotEmpty ? _codigoController.text : null,
      vrCusto: _parseCurrency(_custoController.text),
      margem: double.tryParse(_margemController.text) ?? 0,
      vrVenda: _parseCurrency(_vendaController.text),
      isAtivo: _isAtivo,
    );

    try {
      if (_editingId != null) {
        await SupabaseService.client
            .from('produtos')
            .update(produto.toJson())
            .eq('id', _editingId!);
        _showSnackBar('Produto atualizado com sucesso!');
      } else {
        await SupabaseService.client
            .from('produtos')
            .insert(produto.toJson());
        _showSnackBar('Produto cadastrado com sucesso!');
      }

      _clearForm();
      setState(() => isEditing = false);
      _fetchProdutos();
    } catch (e) {
      _showSnackBar('Erro ao salvar produto: $e', isError: true);
    }
  }

  Future<void> _deleteProduto(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Deseja realmente excluir este produto?'),
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
            .from('produtos')
            .update({'is_excluido': true})
            .eq('id', id);
        _showSnackBar('Produto excluído com sucesso!');
        _fetchProdutos();
      } catch (e) {
        _showSnackBar('Erro ao excluir produto: $e', isError: true);
      }
    }
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
                Flex(
                  direction: isMobile ? Axis.vertical : Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Text(
                      isEditing ? (_editingId != null ? 'Editando Produto' : 'Novo Produto') : 'Cadastro de Produtos',
                      style: TextStyle(fontSize: isMobile ? 18 : 20, fontWeight: FontWeight.bold),
                    ),
                    if (!isEditing)
                      Padding(
                        padding: EdgeInsets.only(top: isMobile ? 12 : 0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _clearForm();
                            setState(() => isEditing = true);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Novo Produto'),
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

    return Form(
      key: _formKey,
      child: Column(
        children: [
          if (isMobile)
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // Nome
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Produto',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Campo obrigatório' : null,
                  ),
                ),

                // Código
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Código Interno',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Custo
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _custoController,
                    decoration: const InputDecoration(
                      labelText: 'Valor de Custo (R\$)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                    onChanged: (_) => _calculateVenda(),
                    onTap: () => _custoController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _custoController.text.length,
                    ),
                  ),
                ),

                // Venda
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _vendaController,
                    decoration: const InputDecoration(
                      labelText: 'Valor de Venda (R\$)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                    onChanged: (_) => _calculateMargem(),
                    onTap: () => _vendaController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _vendaController.text.length,
                    ),
                  ),
                ),

                // Margem
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    controller: _margemController,
                    decoration: const InputDecoration(
                      labelText: 'Margem (%)',
                      border: OutlineInputBorder(),
                      suffixText: '%',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _calculateVenda(),
                    onTap: () => _margemController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _margemController.text.length,
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                // Linha 1: Nome e Código
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Produto',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v?.isEmpty == true ? 'Campo obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        controller: _codigoController,
                        decoration: const InputDecoration(
                          labelText: 'Código Interno',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Linha 2: Custo, Margem e Venda
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _custoController,
                        decoration: const InputDecoration(
                          labelText: 'Valor de Custo (R\$)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CurrencyInputFormatter(),
                        ],
                        onChanged: (_) => _calculateVenda(),
                        onTap: () => _custoController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _custoController.text.length,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _vendaController,
                        decoration: const InputDecoration(
                          labelText: 'Valor de Venda (R\$)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CurrencyInputFormatter(),
                        ],
                        onChanged: (_) => _calculateMargem(),
                        onTap: () => _vendaController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _vendaController.text.length,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _margemController,
                        decoration: const InputDecoration(
                          labelText: 'Margem (%)',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _calculateVenda(),
                        onTap: () => _margemController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _margemController.text.length,
                        ),
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
                  onPressed: _saveProduto,
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
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nome', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Código', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Custo', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Margem', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Venda', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: produtos.map((produto) {
            return DataRow(cells: [
              DataCell(Text(produto.nome)),
              DataCell(Text(produto.codigoInterno ?? '')),
              DataCell(Text(_formatCurrency(produto.vrCusto))),
              DataCell(Text('${produto.margem}%')),
              DataCell(Text(_formatCurrency(produto.vrVenda))),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: produto.isAtivo ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    produto.isAtivo ? 'Ativo' : 'Inativo',
                    style: TextStyle(
                      color: produto.isAtivo ? const Color(0xFF166534) : const Color(0xFF991B1B),
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
                    onPressed: () => _editProduto(produto),
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 20),
                    onPressed: () => _deleteProduto(produto.id!),
                    tooltip: 'Excluir',
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    double value = double.parse(newValue.text);
    final formatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    String newText = formatter.format(value / 100);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
