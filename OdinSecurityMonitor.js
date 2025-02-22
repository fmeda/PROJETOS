import { useState, useEffect, useMemo } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { LineChart, PieChart, RadarChart, BarChart } from "recharts";  // Remover HeatmapChart
import { motion } from "framer-motion";
import { FaShieldAlt, FaNetworkWired, FaRobot, FaFileContract, FaTools } from "react-icons/fa";

export default function OdinSecurityMonitor() {
  const [data, setData] = useState([]);
  const [filter, setFilter] = useState("all");
  const [automatedResponse, setAutomatedResponse] = useState(false);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    const fetchData = async () => {
      try {
        const res = await fetch("/api/security-data");
        const jsonData = await res.json();
        setData(jsonData);
      } catch (err) {
        console.error("Erro ao carregar dados", err);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  const filteredData = useMemo(() => {
    return filter === "all" ? data : data.filter(d => d.type === filter);
  }, [data, filter]);

  const handleAutomatedResponse = async () => {
    try {
      setAutomatedResponse(true);
      await fetch("/api/execute-playbook", { method: "POST" });
      alert("Resposta automatizada acionada!");
    } catch {
      alert("Erro ao executar playbook.");
    } finally {
      setAutomatedResponse(false);
    }
  };

  if (loading) {
    return <div className="text-center p-4 text-lg font-semibold">Carregando dados...</div>;
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4">
      <div className="col-span-3 flex justify-between items-center">
        <select onChange={(e) => setFilter(e.target.value)} className="p-2 border rounded">
          <option value="all">Todos</option>
          <option value="security">Segurança</option>
          <option value="performance">Desempenho</option>
        </select>
        <Button onClick={handleAutomatedResponse} disabled={automatedResponse} className="bg-red-500 text-white p-2 rounded">
          <FaTools className="inline mr-2" /> {automatedResponse ? "Executando..." : "Acionar Resposta Automatizada"}
        </Button>
      </div>
      
      {[{
        title: "Análise Preditiva",
        icon: <FaShieldAlt className="inline mr-2" />, 
        chart: <LineChart width={400} height={200} data={filteredData} />
      }, {
        title: "Monitoramento de Rede",
        icon: <FaNetworkWired className="inline mr-2" />,
        chart: <BarChart width={400} height={200} data={filteredData} />
      }, {
        title: "IA para Detecção de Anomalias",
        icon: <FaRobot className="inline mr-2" />,
        chart: <RadarChart width={300} height={200} data={filteredData} />
      }, {
        title: "Compliance e Auditoria",
        icon: <FaFileContract className="inline mr-2" />,
        chart: <PieChart width={200} height={200} data={filteredData} />
      }].map((item, index) => (
        <motion.div key={index} whileHover={{ scale: 1.1 }}>
          <Card className="shadow-lg p-4">
            <CardContent>
              <h2 className="text-xl font-bold">{item.icon} {item.title}</h2>
              {item.chart}
            </CardContent>
          </Card>
        </motion.div>
      ))}
    </div>
  );
}
