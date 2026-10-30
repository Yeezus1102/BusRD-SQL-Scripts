/* =========================================================
   02_sp_VenderBoleto.sql  -  Entregable E2 (Unidad I)
   Procedimiento de venta corregido: validaciones, transacción,
   bloqueo para impedir doble venta, TRY...CATCH, OUTPUT y demo.
   Ejecutar después de 01_integridad.sql.
   ========================================================= */
USE BusRD;
GO
CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto
    @ViajeID        INT,
    @NumeroAsiento  INT,
    @ClienteID      INT,
    @Canal          VARCHAR(10),
    @Metodo         VARCHAR(15),
    @SimularDemora  BIT = 0,
    @BoletoID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Precio DECIMAL(10,2), @Estado VARCHAR(15), @AutobusID INT;

    SET @BoletoID = NULL;
    BEGIN TRY
        BEGIN TRAN;

        -- 1) Validaciones
        SELECT @Estado = v.Estado, @AutobusID = v.AutobusID, @Precio = r.PrecioBase
        FROM dbo.Viajes v
        JOIN dbo.Rutas r ON r.RutaID = v.RutaID
        WHERE v.ViajeID = @ViajeID;

        IF @Estado IS NULL
            THROW 50010, 'El viaje no existe.', 1;
        IF @Estado <> 'Programado'
            THROW 50011, 'El viaje no está programado para venta.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Asientos
                       WHERE AutobusID = @AutobusID AND NumeroAsiento = @NumeroAsiento)
            THROW 50012, 'El asiento no existe en el autobús del viaje.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WHERE ClienteID = @ClienteID)
            THROW 50013, 'El cliente no existe.', 1;
        IF @Canal NOT IN ('Taquilla', 'Web')
            THROW 50014, 'Canal no válido.', 1;
        IF @Metodo NOT IN ('Efectivo', 'Tarjeta', 'Transferencia')
            THROW 50015, 'Método de pago no válido.', 1;

        -- 2) Concurrencia: UPDLOCK + HOLDLOCK toma el bloqueo sobre el asiento
        --    y lo mantiene hasta COMMIT/ROLLBACK. Una segunda venta del mismo
        --    asiento espera aquí y, al liberarse, encuentra el boleto activo.
        --    Con el índice UX_Boletos_AsientoActivo (E1) este bloqueo es una
        --    búsqueda (seek), no un recorrido de la tabla.
        IF EXISTS (SELECT 1 FROM dbo.Boletos WITH (UPDLOCK, HOLDLOCK)
                   WHERE ViajeID = @ViajeID
                     AND NumeroAsiento = @NumeroAsiento
                     AND Estado = 'Activo')
            THROW 50016, 'El asiento ya está vendido.', 1;

        -- 3) Demo: simula la demora del cobro dentro de la transacción
        IF @SimularDemora = 1
            WAITFOR DELAY '00:00:10';

        -- 4) Boleto y pago en la misma transacción
        INSERT dbo.Boletos (ViajeID, NumeroAsiento, ClienteID, FechaVenta, Canal, Precio, Estado)
        VALUES (@ViajeID, @NumeroAsiento, @ClienteID, SYSDATETIME(), @Canal, @Precio, 'Activo');

        SET @BoletoID = SCOPE_IDENTITY();

        INSERT dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
        VALUES (@BoletoID, @Precio, @Metodo, SYSDATETIME());

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SET @BoletoID = NULL;
        THROW;
    END CATCH
END
GO
