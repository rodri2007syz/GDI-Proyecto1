document.addEventListener("DOMContentLoaded", () => {
    verificarConexion();
    cargarClientes();
    ejecutarReporte();
});

function mostrarMensaje(texto, esError = false) {
    const toast = document.getElementById("toast");
    toast.textContent = texto;
    toast.style.backgroundColor = esError ? "#dc3545" : "#198754";
    toast.style.display = "block";
    setTimeout(() => { toast.style.display = "none"; }, 3500);
}

function cambiarTab(tabId, btn) {
    document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
    document.querySelectorAll(".tab-btn").forEach(el => el.classList.remove("active"));
    document.getElementById("sec-" + tabId).classList.add("active");
    btn.classList.add("active");
}

// 1. PRUEBA DE CONEXIÓN EN TIEMPO REAL
async function verificarConexion() {
    const badge = document.getElementById("badge-conexion");
    const info = document.getElementById("info-conexion");
    try {
        const res = await fetch("/api/status");
        const data = await res.json();
        if (data.ok) {
            badge.textContent = `ONLINE (${data.latencia} ms)`;
            badge.className = "badge badge-online";
            info.textContent = `Conectado a BD "${data.bd}" | Motor: ${data.motor}`;
        } else {
            throw new Error(data.error);
        }
    } catch (err) {
        badge.textContent = "OFFLINE";
        badge.className = "badge badge-offline";
        info.textContent = "Error de conexión: " + err.message;
    }
}

// 2. LISTAR Y BUSCAR CLIENTES
async function cargarClientes() {
    const q = document.getElementById("buscador-cliente").value;
    const res = await fetch(`/api/clientes?q=${encodeURIComponent(q)}`);
    const clientes = await res.json();
    const tbody = document.getElementById("tbody-clientes");
    tbody.innerHTML = "";

    clientes.forEach(c => {
        const tr = document.createElement("tr");
        tr.innerHTML = `
            <td>${c.id}</td>
            <td><strong>${c.dni_ruc}</strong></td>
            <td>${c.nombre}</td>
            <td>${c.telefono}</td>
            <td>${c.direccion}</td>
            <td>
                <button class="btn btn-edit" onclick='editarCliente(${JSON.stringify(c)})'>Editar</button>
                <button class="btn btn-delete" onclick="eliminarCliente(${c.id})">Eliminar</button>
            </td>
        `;
        tbody.appendChild(tr);
    });
}

// 3. INSERTAR O MODIFICAR CLIENTE (LLAMA A PROCEDIMIENTOS ALMACENADOS)
document.getElementById("form-cliente").addEventListener("submit", async (e) => {
    e.preventDefault();
    const id = document.getElementById("cli-id").value;
    const payload = {
        id: id,
        dni_ruc: document.getElementById("cli-dni").value.trim(),
        nombre: document.getElementById("cli-nombre").value.trim(),
        telefono: document.getElementById("cli-telefono").value.trim(),
        direccion: document.getElementById("cli-direccion").value.trim(),
        email: document.getElementById("cli-email").value.trim(),
        referencia: ""
    };

    const metodo = id ? "PUT" : "POST";
    const res = await fetch("/api/clientes", {
        method: metodo,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });
    const data = await res.json();

    if (res.ok) {
        mostrarMensaje(data.mensaje);
        resetearFormulario();
        cargarClientes();
    } else {
        mostrarMensaje("Error BD: " + data.error, true);
    }
});

function editarCliente(c) {
    document.getElementById("form-titulo").textContent = `Modificar Cliente #${c.id}`;
    document.getElementById("cli-id").value = c.id;
    document.getElementById("cli-dni").value = c.dni_ruc;
    document.getElementById("cli-dni").disabled = true; // DNI/RUC no se edita
    document.getElementById("cli-nombre").value = c.nombre;
    document.getElementById("cli-telefono").value = c.telefono;
    document.getElementById("cli-direccion").value = c.direccion;
    document.getElementById("cli-email").value = c.email || "";
    document.getElementById("btn-guardar").textContent = "Actualizar Cliente";
    document.getElementById("btn-cancelar").style.display = "inline-block";
}

function resetearFormulario() {
    document.getElementById("form-titulo").textContent = "Registrar Nuevo Cliente";
    document.getElementById("form-cliente").reset();
    document.getElementById("cli-id").value = "";
    document.getElementById("cli-dni").disabled = false;
    document.getElementById("btn-guardar").textContent = "Guardar Cliente";
    document.getElementById("btn-cancelar").style.display = "none";
}

// 4. BORRADO LÓGICO DE CLIENTE
async function eliminarCliente(id) {
    if (!confirm("¿Desea dar de baja (borrado lógico) a este cliente?")) return;
    const res = await fetch(`/api/clientes/${id}`, { method: "DELETE" });
    const data = await res.json();
    if (res.ok) {
        mostrarMensaje(data.mensaje);
        cargarClientes();
    } else {
        mostrarMensaje(data.error, true);
    }
}

// 5. EJECUTAR CUALQUIERA DE LOS 10 REPORTES
async function ejecutarReporte() {
    const num = document.getElementById("select-reporte").value;
    const res = await fetch(`/api/reportes/${num}`);
    const filas = await res.json();

    const thead = document.getElementById("thead-reporte");
    const tbody = document.getElementById("tbody-reporte");
    thead.innerHTML = "";
    tbody.innerHTML = "";

    if (!filas || filas.length === 0) {
        tbody.innerHTML = "<tr><td>No se encontraron registros para este reporte.</td></tr>";
        return;
    }

    const columnas = Object.keys(filas[0]);
    const trHead = document.createElement("tr");
    columnas.forEach(col => {
        const th = document.createElement("th");
        th.textContent = col.replace(/_/g, " ").toUpperCase();
        trHead.appendChild(th);
    });
    thead.appendChild(trHead);

    filas.forEach(fila => {
        const tr = document.createElement("tr");
        columnas.forEach(col => {
            const td = document.createElement("td");
            td.textContent = fila[col] !== null ? fila[col] : "-";
            tr.appendChild(td);
        });
        tbody.appendChild(tr);
    });
}