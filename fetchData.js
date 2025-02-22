export async function fetchData(url) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Erro ao buscar dados: ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      console.error("Erro ao carregar dados", error);
      return [];
    }
  }
  