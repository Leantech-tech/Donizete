import 'package:flutter/material.dart';
import 'clientes_page.dart';
import 'produtos_page.dart';
import 'lancamentos_page.dart';
import 'dashboard_page.dart';
import 'despesas_page.dart';
import 'relatorio_page.dart';
import 'auth_page.dart';
import '../services/supabase_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  Future<void> _signOut() async {
    try {
      await SupabaseService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sair: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  final List<Widget> _pages = const [
    DashboardPage(),
    LancamentosPage(),
    ClientesPage(),
    ProdutosPage(),
    DespesasPage(),
    RelatorioPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 850;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: isMobile
          ? AppBar(
              title: const Text('Donizete Vendas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              actions: [
                IconButton(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, color: Colors.red),
                ),
              ],
            )
          : null,
      drawer: isMobile
          ? Drawer(
              child: Column(
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(color: Color(0xFF4F46E5)),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_cart_checkout, size: 48, color: Colors.white),
                          const SizedBox(height: 12),
                          const Text(
                            'Donizete Vendas',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildDrawerItem(0, Icons.dashboard, 'Painel'),
                  _buildDrawerItem(1, Icons.shopping_bag, 'Vendas'),
                  _buildDrawerItem(2, Icons.people, 'Clientes'),
                  _buildDrawerItem(3, Icons.inventory_2, 'Produtos'),
                  _buildDrawerItem(4, Icons.money_off, 'Despesas'),
                  _buildDrawerItem(5, Icons.bar_chart, 'Relatório'),
                  const Spacer(),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sair', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      _signOut();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header (Only for Desktop)
              if (!isMobile)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Sistema de Gestão - Controle de Clientes, Produtos e Vendas',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // Navigation
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildNavButton(0, Icons.dashboard, 'Painel', isMobile),
                          _buildNavButton(1, Icons.shopping_bag, 'Vendas', isMobile),
                          _buildNavButton(2, Icons.people, 'Clientes', isMobile),
                          _buildNavButton(3, Icons.inventory_2, 'Produtos', isMobile),
                          _buildNavButton(4, Icons.money_off, 'Despesas', isMobile),
                          _buildNavButton(5, Icons.bar_chart, 'Relatório', isMobile),
                          ElevatedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Sair', style: TextStyle(fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.red.shade600,
                              elevation: 0,
                              side: BorderSide(color: Colors.red.shade100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              // Content
              _pages[_selectedIndex],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF6B7280),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF6B7280),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildNavButton(int index, IconData icon, String label, bool isMobile) {
    final isSelected = _selectedIndex == index;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: () => setState(() => _selectedIndex = index),
        icon: Icon(
          icon,
          size: isMobile ? 18 : 20,
          color: isSelected ? Colors.white : const Color(0xFF6B7280),
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 12 : 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          foregroundColor: isSelected ? Colors.white : const Color(0xFF6B7280),
          elevation: isSelected ? 8 : 0,
          shadowColor: const Color(0xFF4F46E5).withOpacity(0.4),
          side: isSelected ? null : BorderSide(color: Colors.grey.shade200),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 20,
            vertical: isMobile ? 12 : 16,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
