import { LineChart, BarChart, RadarChart, PieChart } from "recharts";  // Recharts gráficos
import { FaShieldAlt, FaNetworkWired, FaRobot, FaFileContract } from "react-icons/fa";

const ChartIcons = {
  "shield-alt": <FaShieldAlt className="inline mr-2" />,
  "network-wired": <FaNetworkWired className="inline mr-2" />,
  "robot": <FaRobot className="inline mr-2" />,
  "file-contract": <FaFileContract className="inline mr-2" />
};

const ChartTypes = {
  LineChart: LineChart,
  BarChart: BarChart,
  RadarChart: RadarChart,
  PieChart: PieChart
};

export function ChartCard({ title, icon, chart, data }) {
  const ChartComponent = ChartTypes[chart];

  return (
    <div className="motion.div" whileHover={{ scale: 1.1 }}>
      <div className="shadow-lg p-4">
        <h2 className="text-xl font-bold">{ChartIcons[icon]} {title}</h2>
        <ChartComponent width={400} height={200} data={data} />
      </div>
    </div>
  );
}
