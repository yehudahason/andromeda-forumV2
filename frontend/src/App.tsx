import { BrowserRouter, Routes, Route } from "react-router-dom";
import AuthPage from "./pages/AuthPage";
import Home2 from "./pages/Home2";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home2 />} />
        <Route path="/auth" element={<AuthPage />} />
      </Routes>
    </BrowserRouter>
  );
}
