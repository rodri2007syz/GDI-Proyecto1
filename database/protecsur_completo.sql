-- =========================================================================
-- BASE DE DATOS PROTECSUR E.I.R.L. - ENTREGA 5 (POSTGRESQL NATIVO)
-- =========================================================================
DROP DATABASE IF EXISTS protecsur;
CREATE DATABASE protecsur ENCODING 'UTF8';

-- CONECTARSE A 'protecsur' ANTES DE EJECUTAR LO SIGUIENTE (\c protecsur)

-- 1. TABLAS PRINCIPALES (CON BORRADO LÓGICO 'activo')
CREATE TABLE CLIENTE (
    ID_cliente SERIAL PRIMARY KEY,
    DNI_RUC VARCHAR(11) NOT NULL UNIQUE,
    Nombre_razon_social VARCHAR(100) NOT NULL,
    Telefono CHAR(9) NOT NULL,
    Direccion VARCHAR(100) NOT NULL,
    Email VARCHAR(80) NULL,
    Referencia VARCHAR(100) NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_cliente_doc CHECK (DNI_RUC ~ '^([0-9]{8}|[0-9]{11})$'),
    CONSTRAINT ck_cliente_tel CHECK (Telefono ~ '^[0-9]{9}$'),
    CONSTRAINT ck_cliente_mail CHECK (Email IS NULL OR Email ~ '^.+@.+\..+$')
);

CREATE TABLE PROVEEDOR (
    ID_proveedor SERIAL PRIMARY KEY,
    RUC CHAR(11) NOT NULL UNIQUE,
    Razon_social VARCHAR(100) NOT NULL,
    Telefono CHAR(9) NOT NULL,
    Direccion VARCHAR(100) NOT NULL,
    Referencia VARCHAR(100) NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_proveedor_ruc CHECK (RUC ~ '^[0-9]{11}$'),
    CONSTRAINT ck_proveedor_tel CHECK (Telefono ~ '^[0-9]{9}$')
);

CREATE TABLE TECNICO (
    Codigo_tecnico SERIAL PRIMARY KEY,
    Nombre_completo VARCHAR(100) NOT NULL,
    Especialidad VARCHAR(60) NOT NULL,
    Telefono CHAR(9) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_tecnico_tel CHECK (Telefono ~ '^[0-9]{9}$')
);

CREATE TABLE PRODUCTO (
    ID_producto SERIAL PRIMARY KEY,
    Nombre VARCHAR(80) NOT NULL,
    Descripcion VARCHAR(200) NULL,
    Precio NUMERIC(10,2) NOT NULL,
    Stock INT NOT NULL DEFAULT 0,
    ID_proveedor INT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_producto_precio CHECK (Precio > 0),
    CONSTRAINT ck_producto_stock CHECK (Stock >= 0),
    CONSTRAINT fk_producto_proveedor FOREIGN KEY (ID_proveedor)
        REFERENCES PROVEEDOR (ID_proveedor) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE COTIZACION (
    Numero_cotizacion CHAR(8) NOT NULL PRIMARY KEY,
    Fecha_cotizacion DATE NOT NULL DEFAULT CURRENT_DATE,
    Mano_obra NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    Estado VARCHAR(10) NOT NULL DEFAULT 'Pendiente',
    ID_cliente INT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_cotizacion_num CHECK (Numero_cotizacion ~ '^COT-[0-9]{4}$'),
    CONSTRAINT ck_cotizacion_mano CHECK (Mano_obra >= 0),
    CONSTRAINT ck_cotizacion_estado CHECK (Estado IN ('Pendiente', 'Aprobada', 'Rechazada')),
    CONSTRAINT fk_cotizacion_cliente FOREIGN KEY (ID_cliente)
        REFERENCES CLIENTE (ID_cliente) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE SERVICIO (
    ID_servicio SERIAL PRIMARY KEY,
    Tipo_servicio VARCHAR(15) NOT NULL,
    Descripcion VARCHAR(200) NOT NULL,
    Fecha_programada DATE NOT NULL,
    Estado VARCHAR(15) NOT NULL DEFAULT 'Programado',
    Numero_cotizacion CHAR(8) NOT NULL UNIQUE,
    Codigo_tecnico INT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_servicio_tipo CHECK (Tipo_servicio IN ('Instalación', 'Mantenimiento')),
    CONSTRAINT ck_servicio_estado CHECK (Estado IN ('Programado', 'En ejecución', 'Finalizado')),
    CONSTRAINT fk_servicio_cotizacion FOREIGN KEY (Numero_cotizacion)
        REFERENCES COTIZACION (Numero_cotizacion) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_servicio_tecnico FOREIGN KEY (Codigo_tecnico)
        REFERENCES TECNICO (Codigo_tecnico) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE DETALLE_COTIZACION (
    Numero_cotizacion CHAR(8) NOT NULL,
    ID_producto INT NOT NULL,
    Cantidad INT NOT NULL,
    Precio_unitario NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (Numero_cotizacion, ID_producto),
    CONSTRAINT ck_detalle_cantidad CHECK (Cantidad > 0),
    CONSTRAINT ck_detalle_precio CHECK (Precio_unitario > 0),
    CONSTRAINT fk_detalle_cotizacion FOREIGN KEY (Numero_cotizacion)
        REFERENCES COTIZACION (Numero_cotizacion) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (ID_producto)
        REFERENCES PRODUCTO (ID_producto) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- TABLA DE AUDITORÍA PARA TRIGGERS
CREATE TABLE AUDITORIA_SISTEMA (
    id_log SERIAL PRIMARY KEY,
    tabla_afectada VARCHAR(40) NOT NULL,
    operacion VARCHAR(15) NOT NULL,
    registro_id VARCHAR(50) NOT NULL,
    detalle TEXT,
    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. TRIGGERS (AUDITORÍA Y REGLAS DE NEGOCIO)
CREATE OR REPLACE FUNCTION fn_auditar_cambios() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO AUDITORIA_SISTEMA(tabla_afectada, operacion, registro_id, detalle)
        VALUES (TG_TABLE_NAME, 'INSERT', ROW_TO_JSON(NEW)::TEXT, 'Nuevo registro insertado');
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO AUDITORIA_SISTEMA(tabla_afectada, operacion, registro_id, detalle)
        VALUES (TG_TABLE_NAME, 'UPDATE', ROW_TO_JSON(NEW)::TEXT, 'Registro actualizado / borrado lógico');
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditoria_cliente
AFTER INSERT OR UPDATE ON CLIENTE
FOR EACH ROW EXECUTE FUNCTION fn_auditar_cambios();

CREATE TRIGGER trg_auditoria_cotizacion
AFTER INSERT OR UPDATE ON COTIZACION
FOR EACH ROW EXECUTE FUNCTION fn_auditar_cambios();

CREATE TRIGGER trg_auditoria_servicio
AFTER INSERT OR UPDATE ON SERVICIO
FOR EACH ROW EXECUTE FUNCTION fn_auditar_cambios();

-- Trigger de negocio: Validar que un servicio solo se cree si la cotización está 'Aprobada'
CREATE OR REPLACE FUNCTION fn_validar_cotizacion_aprobada() RETURNS TRIGGER AS $$
DECLARE
    v_estado VARCHAR(10);
BEGIN
    SELECT Estado INTO v_estado FROM COTIZACION WHERE Numero_cotizacion = NEW.Numero_cotizacion;
    IF v_estado <> 'Aprobada' THEN
        RAISE EXCEPTION 'No se puede programar servicio: la cotización % no está Aprobada (Estado actual: %)', NEW.Numero_cotizacion, v_estado;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_servicio_cotizacion
BEFORE INSERT ON SERVICIO
FOR EACH ROW EXECUTE FUNCTION fn_validar_cotizacion_aprobada();

-- 3. PROCEDIMIENTOS ALMACENADOS PARA CRUD (INSERTAR, MODIFICAR, BORRADO LÓGICO)
CREATE OR REPLACE PROCEDURE sp_insertar_cliente(
    p_dni_ruc VARCHAR, p_nombre VARCHAR, p_tel CHAR, p_dir VARCHAR, p_email VARCHAR, p_ref VARCHAR
) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO CLIENTE (DNI_RUC, Nombre_razon_social, Telefono, Direccion, Email, Referencia)
    VALUES (p_dni_ruc, p_nombre, p_tel, p_dir, p_email, p_ref);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_actualizar_cliente(
    p_id INT, p_nombre VARCHAR, p_tel CHAR, p_dir VARCHAR, p_email VARCHAR, p_ref VARCHAR
) LANGUAGE plpgsql AS $$
BEGIN
    UPDATE CLIENTE
    SET Nombre_razon_social = p_nombre, Telefono = p_tel, Direccion = p_dir, Email = p_email, Referencia = p_ref
    WHERE ID_cliente = p_id AND activo = TRUE;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_eliminar_cliente_logico(p_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE CLIENTE SET activo = FALSE WHERE ID_cliente = p_id;
END;
$$;

-- 4. VISTA DE ATRIBUTOS DERIVADOS
CREATE OR REPLACE VIEW VW_COTIZACION_TOTALES AS
SELECT
    c.Numero_cotizacion, c.Fecha_cotizacion, c.ID_cliente, c.Estado,
    COALESCE(SUM(d.Cantidad * d.Precio_unitario), 0.00) AS Subtotal_productos,
    c.Mano_obra,
    COALESCE(SUM(d.Cantidad * d.Precio_unitario), 0.00) + c.Mano_obra AS Total,
    ROUND((COALESCE(SUM(d.Cantidad * d.Precio_unitario), 0.00) + c.Mano_obra) * 0.50, 2) AS Adelanto
FROM COTIZACION c
LEFT JOIN DETALLE_COTIZACION d ON d.Numero_cotizacion = c.Numero_cotizacion
WHERE c.activo = TRUE
GROUP BY c.Numero_cotizacion, c.Fecha_cotizacion, c.ID_cliente, c.Estado, c.Mano_obra;

-- 5. FUNCIONES/PROCEDIMIENTOS DE REPORTE (10 REPORTES - 7 CON JOIN)
-- Reporte 1 (JOIN): Liquidación financiera de cotizaciones (Total, Adelanto 50%, Saldo 50%)
CREATE OR REPLACE FUNCTION fn_rep1_liquidacion_cotizaciones()
RETURNS TABLE (numero CHAR, fecha DATE, cliente VARCHAR, estado VARCHAR, total NUMERIC, adelanto NUMERIC, saldo NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT v.Numero_cotizacion, v.Fecha_cotizacion, c.Nombre_razon_social, v.Estado,
           v.Total, v.Adelanto, ROUND(v.Total - v.Adelanto, 2)
    FROM VW_COTIZACION_TOTALES v
    INNER JOIN CLIENTE c ON c.ID_cliente = v.ID_cliente
    ORDER BY v.Fecha_cotizacion DESC;
END;
$$;

-- Reporte 2 (JOIN): Orden de compra a proveedores para servicios activos
CREATE OR REPLACE FUNCTION fn_rep2_orden_compra_proveedores()
RETURNS TABLE (proveedor VARCHAR, producto VARCHAR, unidades_requeridas BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT pr.Razon_social, p.Nombre, SUM(dc.Cantidad)
    FROM SERVICIO s
    INNER JOIN COTIZACION co ON co.Numero_cotizacion = s.Numero_cotizacion
    INNER JOIN DETALLE_COTIZACION dc ON dc.Numero_cotizacion = co.Numero_cotizacion
    INNER JOIN PRODUCTO p ON p.ID_producto = dc.ID_producto
    INNER JOIN PROVEEDOR pr ON pr.ID_proveedor = p.ID_proveedor
    WHERE s.Estado IN ('Programado', 'En ejecución') AND s.activo = TRUE
    GROUP BY pr.Razon_social, p.Nombre;
END;
$$;

-- Reporte 3 (JOIN): Seguimiento de cotizaciones pendientes y días de antigüedad
CREATE OR REPLACE FUNCTION fn_rep3_cotizaciones_pendientes()
RETURNS TABLE (numero CHAR, fecha DATE, dias_espera INT, cliente VARCHAR, telefono CHAR, total NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT v.Numero_cotizacion, v.Fecha_cotizacion, (CURRENT_DATE - v.Fecha_cotizacion)::INT,
           cl.Nombre_razon_social, cl.Telefono, v.Total
    FROM VW_COTIZACION_TOTALES v
    INNER JOIN CLIENTE cl ON cl.ID_cliente = v.ID_cliente
    WHERE v.Estado = 'Pendiente'
    ORDER BY dias_espera DESC;
END;
$$;

-- Reporte 4 (JOIN): Hoja de ruta de servicios para técnicos
CREATE OR REPLACE FUNCTION fn_rep4_hoja_ruta_tecnicos()
RETURNS TABLE (fecha DATE, tipo VARCHAR, tecnico VARCHAR, cliente VARCHAR, direccion VARCHAR, estado VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT s.Fecha_programada, s.Tipo_servicio, t.Nombre_completo,
           cl.Nombre_razon_social, cl.Direccion, s.Estado
    FROM SERVICIO s
    INNER JOIN TECNICO t ON t.Codigo_tecnico = s.Codigo_tecnico
    INNER JOIN COTIZACION co ON co.Numero_cotizacion = s.Numero_cotizacion
    INNER JOIN CLIENTE cl ON cl.ID_cliente = co.ID_cliente
    WHERE s.activo = TRUE
    ORDER BY s.Fecha_programada DESC;
END;
$$;

-- Reporte 5 (JOIN): Catálogo de productos con datos del proveedor
CREATE OR REPLACE FUNCTION fn_rep5_catalogo_productos_proveedor()
RETURNS TABLE (id_prod INT, producto VARCHAR, precio NUMERIC, stock INT, proveedor VARCHAR, tel_proveedor CHAR)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT p.ID_producto, p.Nombre, p.Precio, p.Stock, pr.Razon_social, pr.Telefono
    FROM PRODUCTO p
    INNER JOIN PROVEEDOR pr ON pr.ID_proveedor = p.ID_proveedor
    WHERE p.activo = TRUE ORDER BY p.ID_producto;
END;
$$;

-- Reporte 6 (JOIN): Carga de trabajo y servicios ejecutados por técnico
CREATE OR REPLACE FUNCTION fn_rep6_productividad_tecnicos()
RETURNS TABLE (codigo INT, tecnico VARCHAR, especialidad VARCHAR, total_servicios BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT t.Codigo_tecnico, t.Nombre_completo, t.Especialidad, COUNT(s.ID_servicio)
    FROM TECNICO t
    LEFT JOIN SERVICIO s ON s.Codigo_tecnico = t.Codigo_tecnico AND s.activo = TRUE
    WHERE t.activo = TRUE
    GROUP BY t.Codigo_tecnico, t.Nombre_completo, t.Especialidad;
END;
$$;

-- Reporte 7 (JOIN): Detalle desglosado de equipos por cada cotización
CREATE OR REPLACE FUNCTION fn_rep7_detalle_cotizaciones()
RETURNS TABLE (numero CHAR, cliente VARCHAR, equipo VARCHAR, cantidad INT, precio_pactado NUMERIC, subtotal NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT dc.Numero_cotizacion, c.Nombre_razon_social, p.Nombre,
           dc.Cantidad, dc.Precio_unitario, (dc.Cantidad * dc.Precio_unitario)
    FROM DETALLE_COTIZACION dc
    INNER JOIN COTIZACION cot ON cot.Numero_cotizacion = dc.Numero_cotizacion
    INNER JOIN CLIENTE c ON c.ID_cliente = cot.ID_cliente
    INNER JOIN PRODUCTO p ON p.ID_producto = dc.ID_producto
    ORDER BY dc.Numero_cotizacion;
END;
$$;

-- Reporte 8: Clientes activos registrados
CREATE OR REPLACE FUNCTION fn_rep8_clientes_activos()
RETURNS TABLE (id INT, dni_ruc VARCHAR, nombre VARCHAR, telefono CHAR, direccion VARCHAR, email VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT ID_cliente, DNI_RUC, Nombre_razon_social, Telefono, Direccion, Email
    FROM CLIENTE WHERE activo = TRUE ORDER BY ID_cliente DESC;
END;
$$;

-- Reporte 9: Productos con stock bajo (<= 6 unidades)
CREATE OR REPLACE FUNCTION fn_rep9_stock_critico()
RETURNS TABLE (id INT, nombre VARCHAR, stock INT, precio NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT ID_producto, Nombre, Stock, Precio FROM PRODUCTO WHERE activo = TRUE AND Stock <= 6;
END;
$$;

-- Reporte 10: Bitácora de auditoría generada por Triggers
CREATE OR REPLACE FUNCTION fn_rep10_auditoria()
RETURNS TABLE (id INT, tabla VARCHAR, op VARCHAR, detalle TEXT, fecha TIMESTAMP)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT id_log, tabla_afectada, operacion, detalle, fecha_hora
    FROM AUDITORIA_SISTEMA ORDER BY id_log DESC LIMIT 20;
END;
$$;

-- 6. INSERCIÓN DE DATOS DE PRUEBA AMPLIADOS (DML)
INSERT INTO CLIENTE (DNI_RUC, Nombre_razon_social, Telefono, Direccion, Email, Referencia) VALUES
('20458796321', 'Clínica Dental Sonrisas Arequipa S.A.C.', '959412365', 'Av. Trinidad Morán G-14, Cayma', 'contacto@sonrisasaqp.pe', 'Segundo piso, costado farmacia'),
('72456321', 'Juan Carlos Pérez Gómez', '987451235', 'Av. Ejército 123, Yanahuara', 'juan.perez@gmail.com', 'Frente a la clínica'),
('45896314', 'María Elena Valdivia Carpio', '958741236', 'Urb. Quinta Samay B-12, Cayma', 'mvaldivia@hotmail.com', 'Ingresando por pórtico'),
('20608954123', 'Boticas Salud Sur E.I.R.L.', '954123789', 'Calle Mercaderes 215, Cercado', 'logistica@saludsur.pe', 'A media cuadra Plaza de Armas'),
('70985412', 'Carlos Alberto Mendoza Ríos', '984512369', 'Av. Parra 410, Cercado', 'cmendoza@outlook.com', 'Grifo Primax'),
('20512369874', 'Restaurante El Rocoto Arequipeño S.R.L.', '958147258', 'Av. Dolores 118, J.L.B. y Rivero', 'admin@elrocoto.pe', 'Frente al parque');

INSERT INTO PROVEEDOR (RUC, Razon_social, Telefono, Direccion, Referencia) VALUES
('20541236987', 'Hikvision Perú Mayoristas S.A.C.', '959123459', 'Calle Las Tiendas 456, Cercado', 'A media cuadra del parque Duhamel'),
('20601478523', 'Dahua Technology Distribuidora Sur S.R.L.', '958745632', 'Av. Goyeneche 318, Cercado', 'Edificio Empresarial Of. 204'),
('20498523641', 'Importaciones Redes y Fibra Sur S.A.C.', '959852147', 'Av. Mariscal Castilla 712, Mariano Melgar', 'Frente al estadio');

INSERT INTO TECNICO (Nombre_completo, Especialidad, Telefono) VALUES
('Rodrigo Alejandro Pérez Mamani', 'Instalador CCTV y Configuración IP', '987654321'),
('Miguel Ángel Quispe Condori', 'Cableado Estructurado y Redes', '958412369'),
('Luis Fernando Huamán Tito', 'Control de Acceso y Alarmas', '957412852');

INSERT INTO PRODUCTO (Nombre, Descripcion, Precio, Stock, ID_proveedor) VALUES
('Cámara IP Bala 2MP Hikvision', 'Cámara IP 1080p exteriores IP67', 145.00, 15, 1),
('Grabador DVR 4 Canales Hikvision', 'DVR AcuSense 4CH 1080p', 240.00, 6, 1),
('Bobina Cable UTP Cat6 100% Cobre', 'Caja de 305 metros', 390.00, 5, 3),
('Cámara Domo Dahua 4MP Full Color', 'Visión nocturna a color', 185.00, 10, 2),
('Disco Duro Vigilancia 2TB WD Purple', 'Almacenamiento continuo 24/7', 260.00, 4, 1);

INSERT INTO COTIZACION (Numero_cotizacion, Fecha_cotizacion, Mano_obra, Estado, ID_cliente) VALUES
('COT-0001', '2026-09-02', 320.00, 'Aprobada', 1),
('COT-0002', '2026-09-05', 450.00, 'Aprobada', 2),
('COT-0003', '2026-09-08', 600.00, 'Pendiente', 3),
('COT-0004', '2026-09-12', 500.00, 'Aprobada', 4),
('COT-0005', '2026-09-15', 280.00, 'Pendiente', 5);

INSERT INTO DETALLE_COTIZACION (Numero_cotizacion, ID_producto, Cantidad, Precio_unitario) VALUES
('COT-0001', 1, 4, 140.00),
('COT-0001', 2, 1, 240.00),
('COT-0002', 1, 6, 145.00),
('COT-0002', 3, 1, 390.00),
('COT-0003', 4, 8, 180.00),
('COT-0004', 4, 4, 185.00),
('COT-0004', 5, 1, 260.00),
('COT-0005', 1, 2, 145.00);

INSERT INTO SERVICIO (Tipo_servicio, Descripcion, Fecha_programada, Estado, Numero_cotizacion, Codigo_tecnico) VALUES
('Instalación', 'Instalación de 4 cámaras IP y DVR en clínica dental', '2026-09-06', 'Finalizado', 'COT-0001', 1),
('Instalación', 'Instalación de 6 cámaras y cableado estructurado', '2026-09-10', 'Programado', 'COT-0002', 2),
('Instalación', 'Sistema de videovigilancia Full Color en botica', '2026-09-18', 'En ejecución', 'COT-0004', 3);