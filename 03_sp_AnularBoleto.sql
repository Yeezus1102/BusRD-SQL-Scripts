/* =========================================================
   03_sp_AnularBoleto.sql  -  Entregable E2 (Unidad I)
   Anula un boleto activo y registra el reverso del pago
   (monto negativo) dentro de una transacción.
   Al quedar Anulado, el asiento queda libre (índice filtrado de E1).
   ========================================================= */
USE BusRD;
GO
CREATE OR ALTER PROCEDURE dbo.sp_AnularBoleto
    @BoletoID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Estado VARCHAR(10);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @Estado = Estado
        FROM dbo.Boletos WITH (UPDLOCK, ROWLOCK)
        WHERE BoletoID = @BoletoID;

        IF @Estado IS NULL
            THROW 50020, 'El boleto no existe.', 1;
        IF @Estado <> 'Activo'
            THROW 50021, 'El boleto no está activo.', 1;

        UPDATE dbo.Boletos
        SET Estado = 'Anulado'
        WHERE BoletoID = @BoletoID;

        -- Reverso del pago: mismo método, monto negativo
        INSERT dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
        SELECT BoletoID, -Monto, Metodo, SYSDATETIME()
        FROM dbo.Pagos
        WHERE BoletoID = @BoletoID AND Monto > 0;

        IF @@ROWCOUNT = 0
            THROW 50022, 'El boleto no tiene pago que revertir.', 1;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO
