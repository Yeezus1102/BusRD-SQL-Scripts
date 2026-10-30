/* =========================================================
   05_demo_concurrencia_sesionB.sql  -  VENTANA B (SSMS #2)
   Ejecutar SOLO el bloque indicado, en el momento indicado.
   Usar los mismos valores que en la ventana A.
   ========================================================= */

/* ---------- PARTE 1: reproducción con v0 (en BusRD_Copia) ---------- */
USE BusRD_Copia;
GO
DECLARE @ViajeID INT = 16000, @Asiento INT = 12, @Cliente INT = 1000;  -- CAMBIAR por los datos del grupo
-- Ejecutar 2 o 3 segundos DESPUÉS de haber iniciado la ventana A (dentro de sus 10 segundos).
EXEC dbo.sp_VenderBoleto_v0 @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
     @ClienteID = @Cliente, @Canal = 'Web', @Metodo = 'Tarjeta';

SELECT BoletoID, ViajeID, NumeroAsiento, ClienteID, Canal, Precio, Estado, FechaVenta
FROM dbo.Boletos
WHERE ViajeID = @ViajeID AND NumeroAsiento = @Asiento AND Estado = 'Activo';
-- Resultado esperado: 2 filas activas (la doble venta).
GO

/* ---------- PARTE 2: procedimiento nuevo (en BusRD) ---------- */
USE BusRD;
GO
DECLARE @ViajeID INT = 16000, @Asiento INT = 12, @Cliente INT = 1000, @Boleto INT;  -- CAMBIAR
-- Ejecutar 2 o 3 segundos DESPUÉS de haber iniciado la ventana A de la parte 2.
-- Esta sesión espera a que A termine y luego se rechaza.
BEGIN TRY
    EXEC dbo.sp_VenderBoleto @ViajeID = @ViajeID, @NumeroAsiento = @Asiento,
         @ClienteID = @Cliente, @Canal = 'Web', @Metodo = 'Tarjeta',
         @SimularDemora = 0, @BoletoID = @Boleto OUTPUT;
    SELECT @Boleto AS BoletoGenerado;   -- no debe llegar aquí
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS Error, ERROR_MESSAGE() AS Mensaje;
    -- Resultado esperado: Error 50016, "El asiento ya está vendido."
END CATCH
