import { Link } from "react-router-dom";

export default function NotFound() {
  return (
    <div>
      <h1 className="text-center text-white py-6">404</h1>
      <p>Page not found.</p>

      <Link to="/">Go Home</Link>
    </div>
  );
}
