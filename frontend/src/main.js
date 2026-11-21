import "./style.css";

import { Elm } from "./Main.elm";

/* Tema inicial: a última escolha do jogador (guardada no localStorage do
navegador) ou, na primeira visita, a preferência do sistema operacional.*/
const THEME_KEY = "telmo-tema";
const savedTheme = localStorage.getItem(THEME_KEY);
const systemIsDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
const darkTheme = savedTheme ? savedTheme === "dark" : systemIsDark;

// `flags` é entregue à função `init` do Elm (veja o tipo Flags em Main.elm).
Elm.Main.init({
  node: document.getElementById("app"),
  flags: { darkTheme },
});

// Guarda a escolha quando o botão de tema muda.
document.addEventListener("change", (event) => {
  if (event.target.matches(".theme-controller")) {
    localStorage.setItem(THEME_KEY, event.target.checked ? "dark" : "light");
  }
});
