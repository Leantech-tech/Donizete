import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/despesa_model.dart';
import '../services/supabase_service.dart';

class DespesasPage extends StatefulWidget {
  const DespesasPage({super.key});

  @override
  State<DespesasPage> createState() => _DespesasPageState();
}

class _DespesasPageState extends State<DespesasPage> {
  List<Despesa> despesas = [];
  bool isLoading = true;
  bool isEditing = false;

  final _formKey = GlobalKey<FormState>();
  final _beneficiarioController = TextEditingController();
  final _referenteController = TextEditingController();
  final _valorController = TextEditingController();
  final _dataController = TextEditingController();

  String? _editingId;
  DateTime _selectedData = DateTime.now();

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _fetchDespesas();
    _dataController.text = _dateFormat.format(_selectedData);
  }

  @override
  void dispose() {
    _beneficiarioController.dispose();
    _referenteController.dispose();
    _valorController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  Future<void> _fetchDespesas() async {
    setState(() => isLoading = true);
    try {
      final response = await SupabaseService.client
          .from('despesas')
          .select()
          .eq('is_excluido', false)
          .order('data', ascending: false);

      setState(() {
        despesas = (response as List).map((e) => Despesa.fromJson(e)).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Erro ao carregar despesas: $e', isError: true);
    }
  }

  void _clearForm() {
    _editingId = null;
    _beneficiarioController.clear();
    _referenteController.clear();
    _valorController.text = 'R\$ 0,00';
    _selectedData = DateTime.now();
    _dataController.text = _dateFormat.format(_selectedData);
  }

  double _parseCurrency(String value) {
    if (value.isEmpty) return 0;
    final cleanValue = value.replaceAll(RegExp(r'[^\d,]'), '').replaceAll(',', '.');
    return double.tryParse(cleanValue) ?? 0;
  }

  String _formatCurrency(double value) {
    return _currencyFormat.format(value);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedData,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedData) {
      setState(() {
        _selectedData = picked;
        _dataController.text = _dateFormat.format(_selectedData);
      });
    }
  }

  void _editDespesa(Despesa despesa) {
    _editingId = despesa.id;
    _beneficiarioController.text = despesa.beneficiario;
    _referenteController.text = despesa.referente;
    _valorController.text = _formatCurrency(despesa.valor);
    _selectedData = despesa.data;
    _dataController.text = _dateFormat.format(_selectedData);

    setState(() => isEditing = true);
  }

  Future<void> _saveDespesa() async {
    if (!_formKey.currentState!.validate()) return;

    final valor = _parseCurrency(_valorController.text);

    final despesa = Despesa(
      id: _editingId,
      beneficiario: _beneficiarioController.text,
      referente: _referenteController.text,
      valor: valor,
      data: _selectedData,
    );

    try {
      if (_editingId != null) {
        await SupabaseService.client
            .from('despesas')
            .update(despesa.toJson())
            .eq('id', _editingId!);
        _showSnackBar('Despesa atualizada com sucesso!');
      } else {
        await SupabaseService.client
            .from('despesas')
            .insert(despesa.toJson());
        _showSnackBar('Despesa cadastrada com sucesso!');
      }

      _clearForm();
      setState(() => isEditing = false);
      _fetchDespesas();
    } catch (e) {
      _showSnackBar('Erro ao salvar despesa: $e', isError: true);
    }
  }

  Future<void> _deleteDespesa(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text('Deseja realmente excluir esta despesa?'),
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
            .from('despesas')
            .update({'is_excluido': true})
            .eq('id', id);
        _showSnackBar('Despesa excluída com sucesso!');
        _fetchDespesas();
      } catch (e) {
        _showSnackBar('Erro ao excluir despesa: $e', isError: true);
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
                      isEditing ? (_editingId != null ? 'Editando Despesa' : 'Nova Despesa') : 'Controle de Despesas',
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
                          label: const Text('Nova Despesa'),
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
    final isMobile = MediaQuery.of(context).size.width < 850;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          if (isMobile)
            Column(
              children: [
                _buildTextField(_beneficiarioController, 'Beneficiário', required: true),
                const SizedBox(height: 16),
                _buildTextField(_referenteController, 'Referente', required: true),
                const SizedBox(height: 16),
                _buildCurrencyField(),
                const SizedBox(height: 16),
                _buildDateField(),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildTextField(_beneficiarioController, 'Beneficiário', required: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField(_referenteController, 'Referente', required: true)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildCurrencyField()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDateField()),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveDespesa,
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

  Widget _buildTextField(TextEditingController controller, String label, {bool required = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required ? (v) => v?.isEmpty == true ? 'Campo obrigatório' : null : null,
    );
  }

  Widget _buildCurrencyField() {
    return TextFormField(
      controller: _valorController,
      decoration: const InputDecoration(
        labelText: 'Valor (R\$)',
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        CurrencyInputFormatter(),
      ],
      onTap: () => _valorController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _valorController.text.length,
      ),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _dataController,
      decoration: const InputDecoration(
        labelText: 'Data',
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.calendar_today),
      ),
      readOnly: true,
      onTap: () => _selectDate(context),
    );
  }

  Widget _buildTable() {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Beneficiário', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Referente', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Valor', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: despesas.map((despesa) {
            return DataRow(cells: [
              DataCell(Text(_dateFormat.format(despesa.data))),
              DataCell(Text(despesa.beneficiario)),
              DataCell(Text(despesa.referente)),
              DataCell(Text(_formatCurrency(despesa.valor))),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Color(0xFF94A3B8), size: 20),
                    onPressed: () => _editDespesa(despesa),
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 20),
                    onPressed: () => _deleteDespesa(despesa.id!),
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
