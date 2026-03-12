import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  int _totalProdutos = 0;
  int _totalClientes = 0;
  int _totalVendas = 0;
  double _receitaDia = 0;
  double _despesaDia = 0;
  double _lucroTotal = 0;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      // Fetch Products Count
      final produtosCount = await SupabaseService.client
          .from('produtos')
          .select('id')
          .eq('is_excluido', false);
      
      // Fetch Clients Count
      final clientesCount = await SupabaseService.client
          .from('clientes')
          .select('id')
          .eq('is_excluido', false);

      // Fetch Sales Count and Total Profit (Only for Today)
      final today = DateTime.now().toIso8601String().split('T')[0];
      final salesResponse = await SupabaseService.client
          .from('lancto_cabecalho')
          .select('vr_total_venda, vr_total_lucro')
          .eq('is_excluido', false)
          .eq('dt_emissao', today);

      final salesList = salesResponse as List;
      double totalProfit = 0;
      double totalRevenue = 0;
      for (var sale in salesList) {
        totalProfit += (sale['vr_total_lucro'] ?? 0).toDouble();
        totalRevenue += (sale['vr_total_venda'] ?? 0).toDouble();
      }

      // Fetch Expenses (Only for Today)
      final expensesResponse = await SupabaseService.client
          .from('despesas')
          .select('valor')
          .eq('is_excluido', false)
          .eq('data', today);
      
      final expensesList = expensesResponse as List;
      double totalExpenses = 0;
      for (var expense in expensesList) {
        totalExpenses += (expense['valor'] ?? 0).toDouble();
      }

      setState(() {
        _totalProdutos = (produtosCount as List).length;
        _totalClientes = (clientesCount as List).length;
        _totalVendas = salesList.length;
        _receitaDia = totalRevenue;
        _despesaDia = totalExpenses;
        _lucroTotal = totalProfit;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar estatísticas: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 850;
    final isVerySmall = width < 400;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Painel',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                ),
              ),
              if (!_isLoading)
                IconButton(
                  onPressed: _fetchStats,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Atualizar',
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 100),
                child: CircularProgressIndicator(),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Diminuir o aspecto no celular para os cards serem um pouco mais altos/confortáveis
                double aspectRatio;
                if (isVerySmall) {
                  aspectRatio = 2.8;
                } else if (isMobile) {
                  aspectRatio = 3.2;
                } else {
                  aspectRatio = 3.5;
                }

                return GridView.count(
                  crossAxisCount: width < 600 ? 1 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: width < 600 ? 4.0 : (isMobile ? 2.5 : 3.5),
                  children: [
                    _buildStatCard(
                      'Produtos',
                      _totalProdutos.toString(),
                      Icons.inventory_2,
                      const Color(0xFF4F46E5),
                      isMobile,
                    ),
                    _buildStatCard(
                      'Clientes',
                      _totalClientes.toString(),
                      Icons.people,
                      const Color(0xFF0EA5E9),
                      isMobile,
                    ),
                    _buildStatCard(
                      'Vendas',
                      _totalVendas.toString(),
                      Icons.shopping_bag,
                      const Color(0xFFF59E0B),
                      isMobile,
                    ),
                    _buildStatCard(
                      'Receita do Dia',
                      _currencyFormat.format(_receitaDia),
                      Icons.trending_up,
                      const Color(0xFF8B5CF6),
                      isMobile,
                    ),
                    _buildStatCard(
                      'Despesa do Dia',
                      _currencyFormat.format(_despesaDia),
                      Icons.trending_down,
                      const Color(0xFFEF4444),
                      isMobile,
                    ),
                    _buildStatCard(
                      'Lucro do Dia',
                      _currencyFormat.format(_lucroTotal),
                      Icons.attach_money,
                      const Color(0xFF10B981),
                      isMobile,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                icon,
                size: isMobile ? 60 : 70,
                color: color.withOpacity(0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: isMobile ? 24 : 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 13,
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
