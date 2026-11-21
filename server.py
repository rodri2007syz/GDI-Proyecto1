import json
import os
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import psycopg2
from psycopg2.extras import RealDictCursor
import sys
import webbrowser

def ruta_recurso(relativa):
    """Permite encontrar la carpeta public/ tanto en script normal como dentro del .exe"""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, relativa)



DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "protecsur",
    "user": "postgres",
    "password": "280307"  
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

def probar_conexion_consola():
    print("==================================================================")
    print(" PRUEBA DE CONEXIÓN NATIVA A POSTGRESQL - PROTECSUR E.I.R.L.")
    print("==================================================================")
    t0 = time.time()
    try:
        conn = get_connection()
        latencia = round((time.time() - t0) * 1000, 2)
        cur = conn.cursor()
        cur.execute("SELECT version();")
        version = cur.fetchone()["version"].split(",")[0]
        cur.execute("SELECT COUNT(*) AS total FROM CLIENTE WHERE activo = TRUE;")
        clientes = cur.fetchone()["total"]
        print(f"[OK] Estado       : CONECTADO EXITOSAMENTE ({latencia} ms)")
        print(f"[OK] Base de Datos: {DB_CONFIG['dbname']} en {DB_CONFIG['host']}:{DB_CONFIG['port']}")
        print(f"[OK] Motor SGBD   : {version}")
        print(f"[OK] Prueba Query : {clientes} clientes activos verificados en BD.")
        print("==================================================================\n")
        cur.close()
        conn.close()
    except Exception as e:
        print(f"[ERROR] Fallo de conexión a PostgreSQL: {e}\n")

class ProtecsurHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ruta_recurso("public"), **kwargs)

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(data, default=str).encode("utf-8"))

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        # Endpoint 1: Prueba de conexión en vivo para el frontend
        if path == "/api/status":
            t0 = time.time()
            try:
                conn = get_connection()
                latencia = round((time.time() - t0) * 1000, 2)
                cur = conn.cursor()
                cur.execute("SELECT version();")
                ver = cur.fetchone()["version"].split(",")[0]
                cur.close()
                conn.close()
                self.send_json({"ok": True, "motor": ver, "bd": DB_CONFIG["dbname"], "latencia": latencia})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)

        # Endpoint 2: Listar / Buscar Clientes llamando a la función almacenada
        elif path == "/api/clientes":
            busqueda = params.get("q", [""])[0].lower()
            try:
                conn = get_connection()
                cur = conn.cursor()
                cur.execute("SELECT * FROM fn_rep8_clientes_activos();")
                filas = cur.fetchall()
                if busqueda:
                    filas = [f for f in filas if busqueda in f["nombre"].lower() or busqueda in f["dni_ruc"]]
                cur.close()
                conn.close()
                self.send_json(filas)
            except Exception as e:
                self.send_json({"error": str(e)}, 500)

        # Endpoint 3: Ejecutar cualquiera de los 10 reportes almacenados
        elif path.startswith("/api/reportes/"):
            num = path.split("/")[-1]
            mapa_reportes = {
                "1": "SELECT * FROM fn_rep1_liquidacion_cotizaciones();",
                "2": "SELECT * FROM fn_rep2_orden_compra_proveedores();",
                "3": "SELECT * FROM fn_rep3_cotizaciones_pendientes();",
                "4": "SELECT * FROM fn_rep4_hoja_ruta_tecnicos();",
                "5": "SELECT * FROM fn_rep5_catalogo_productos_proveedor();",
                "6": "SELECT * FROM fn_rep6_productividad_tecnicos();",
                "7": "SELECT * FROM fn_rep7_detalle_cotizaciones();",
                "8": "SELECT * FROM fn_rep8_clientes_activos();",
                "9": "SELECT * FROM fn_rep9_stock_critico();",
                "10": "SELECT * FROM fn_rep10_auditoria();"
            }
            sql = mapa_reportes.get(num)
            if not sql:
                return self.send_json({"error": "Reporte no válido"}, 404)
            try:
                conn = get_connection()
                cur = conn.cursor()
                cur.execute(sql)
                filas = cur.fetchall()
                cur.close()
                conn.close()
                self.send_json(filas)
            except Exception as e:
                self.send_json({"error": str(e)}, 500)
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == "/api/clientes":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            try:
                conn = get_connection()
                cur = conn.cursor()
                # Llamada nativa a PROCEDIMIENTO ALMACENADO
                cur.execute(
                    "CALL sp_insertar_cliente(%s, %s, %s, %s, %s, %s);",
                    (body["dni_ruc"], body["nombre"], body["telefono"], body["direccion"], body.get("email") or None, body.get("referencia") or None)
                )
                conn.commit()
                cur.close()
                conn.close()
                self.send_json({"mensaje": "Cliente registrado vía procedimiento sp_insertar_cliente"})
            except Exception as e:
                self.send_json({"error": str(e)}, 400)

    def do_PUT(self):
        if self.path == "/api/clientes":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            try:
                conn = get_connection()
                cur = conn.cursor()
                # Llamada nativa a PROCEDIMIENTO DE ACTUALIZACIÓN
                cur.execute(
                    "CALL sp_actualizar_cliente(%s, %s, %s, %s, %s, %s);",
                    (int(body["id"]), body["nombre"], body["telefono"], body["direccion"], body.get("email") or None, body.get("referencia") or None)
                )
                conn.commit()
                cur.close()
                conn.close()
                self.send_json({"mensaje": "Cliente actualizado vía procedimiento sp_actualizar_cliente"})
            except Exception as e:
                self.send_json({"error": str(e)}, 400)

    def do_DELETE(self):
        if self.path.startswith("/api/clientes/"):
            id_cliente = int(self.path.split("/")[-1])
            try:
                conn = get_connection()
                cur = conn.cursor()
                # Llamada nativa a PROCEDIMIENTO DE BORRADO LÓGICO
                cur.execute("CALL sp_eliminar_cliente_logico(%s);", (id_cliente,))
                conn.commit()
                cur.close()
                conn.close()
                self.send_json({"mensaje": "Cliente desactivado (borrado lógico) vía sp_eliminar_cliente_logico"})
            except Exception as e:
                self.send_json({"error": str(e)}, 400)

if __name__ == "__main__":
    probar_conexion_consola()
    servidor = HTTPServer(("localhost", 8000), ProtecsurHandler)
    print("Servidor nativo corriendo en http://localhost:8000 (Presiona Ctrl+C para detener)")
    webbrowser.open("http://localhost:8000")
    servidor.serve_forever()