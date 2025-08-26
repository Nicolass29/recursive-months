/*
Essas três views funcionam de forma encadeada:

    1. VW_Generic_Data
        .View inicial, recebe os periodos de inicio o fim digitados pelo usuario para cada ativo.
        .Pegando apenas o type = 'NEW'.
        .Saindo a data formatada nas colunas StartDate e EndDate.Value

    2. VW_Generic_FV
        .Utilizando recusrividade é criado uma lista de meses para cada ativo, incrementando mes a mes.
        .Associa esses meses aos outros itens, itens contabeis, centro de custos...
        .Criando a coluna FLAG que é usada como referencia para outras contas. 
        .Resultado: uma tabela mostrando mês a mês, por ativo e item contábil, algo assim:

        Value_Class Cost_Center Accounting_Item KeyCol  KeyName MonthFormatted  Flag
        123          CC1            ItemA         1      Nome1   202501           1
        ...           ...            ...         ...      ...     ...            ...
        999           CC3           ItemZ         1       Nome1   202512           1


    3. VW_Generic_ProfileRate
        .Também usa recursividade, mas sobre a view VW_Generic_Version (similar à VW_Generic_Data).
        .Ao invés de usar o período definido pelo usuário, considera o final da versão.
        .Calcula a taxa percentual (RatePercent) de cada perfil.SHARE
        .Resultado: distribuição mês a mês por perfil, com a taxa percentual aplicada:

                            Profile RatePercent MonthFormatted
                            GrupoA      0.05       202501
                            GrupoB      0.10       202501


    Em resumo:

        A primeira view define os períodos de interesse.

        A segunda expande esses períodos mês a mês e associa aos ativos/itens contábeis.

        A terceira calcula percentuais por perfil usando a recursividade para distribuir os valores ao longo dos meses da versão.


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

These three views work in a sequential manner:


 1. VW_Generic_Data

  .Initial view, receives start and end periods entered by the user for each asset.
  .Filters only type = 'NEW'.
  .Outputs formatted dates in the columns StartDate and EndDate.

   2. VW_Generic_FV

    Uses recursion to create a month-by-month list for each asset.
    Associates these months with other items, accounting items, cost centers, etc.
    Creates a FLAG column used as a reference for other calculations.
    Result: a table showing month-by-month allocation per asset and accounting item, e.g.:

      Value_Class Cost_Center Accounting_Item KeyCol  KeyName MonthFormatted Flag
      123         CC1           ItemA           1       Name1   202501         1
      ...         ...           ...             ...     ...      ...          ...
      999         CC3          ItemZ           1       Name1   202512         1

  3. VW_Generic_ProfileRate
        .Also uses recursion, but based on VW_Generic_Version (similar to VW_Generic_Data).
        .Instead of using the user-defined period, it considers the version’s end date.
        .Calculates the percentage rate (RatePercent) of each profile/share.
        .Result: month-by-month distribution per profile, with the percentage applied:

          Profile   RatePercent MonthFormatted
          GroupA       0.05        202501
          GroupB       0.10        202501

  
  Summary:

  .The first view defines the periods of interest.
  .The second expands these periods month by month and links them to assets/accounting items.
  .The third calculates percentage rates per profile, using recursion to distribute values across the months of the version.



*/

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
CREATE 
VIEW `VW_Generic_Data` AS
    SELECT 
        `a`.`KeyCol` AS `KeyCol`,
        DATE_FORMAT(`a`.Start_Period,
                '%Y-%m-%d') AS StartDate,
        DATE_FORMAT(`a`.End_Period,
                '%Y-%m-%d') AS EndDate
    FROM
        Source_Table a
    WHERE
        ((a.Asset_Type = 'New')
            AND (a.Start_Period IS NOT NULL)
            AND (a.End_Period IS NOT NULL));

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE 
VIEW `VW_Generic_FV` AS 

WITH RECURSIVE `numbers` AS (
    SELECT 
        `VNA`.`KeyCol` AS `KeyCol`,
        `VNA`.`StartDate` AS `StartMonth`,
        `VNA`.`EndDate` AS `EndMonth`
    FROM
        `VW_Generic_Data` `VNA`
    UNION ALL
    SELECT 
        `n`.`KeyCol` AS `KeyCol`,
        (`n`.`StartMonth` + INTERVAL 1 MONTH) AS `NextMonth`,
        `n`.`EndMonth` AS `EndMonth`
    FROM
        `numbers` `n`
    WHERE
        (`n`.`StartMonth` < `n`.`EndMonth`)
), 

`ranges` AS (
    SELECT 
        `a`.`Value_Class` AS `Value_Class`,
        `a`.`Cost_Center` AS `Cost_Center`,
        `a`.`Accounting_Item` AS `Accounting_Item`,
        `a`.`KeyCol` AS `KeyCol`,
        `a`.`KeyName` AS `KeyName`,
        `nu`.`StartMonth` AS `Month`
    FROM 
        (`Source_Table` `a`
    JOIN `numbers` `nu` 
        ON ((`nu`.`KeyCol` = `a`.`KeyCol`) 
            AND (`nu`.`StartMonth` BETWEEN `a`.`StartDate` AND `nu`.`EndMonth`)))
    WHERE 
        (`a`.`Asset_Type` = 'New')
) 

SELECT DISTINCT 
    `ranges`.`Value_Class` AS `Value_Class`,
    `ranges`.`Cost_Center` AS `Cost_Center`,
    `ranges`.`Accounting_Item` AS `Accounting_Item`,
    `ranges`.`KeyCol` AS `KeyCol`,
    `ranges`.`KeyName` AS `KeyName`,
    DATE_FORMAT(`ranges`.`Month`, '%Y%m') AS `MonthFormatted`,
    1 AS `Flag`
FROM 
    `ranges`
ORDER BY 
    `ranges`.`KeyCol`,
    `ranges`.`Month`;


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE 
VIEW `VW_Generic_ProfileRate` AS 

WITH RECURSIVE `months` AS (
    SELECT 
        `DV`.`VersionName` AS `VersionName`,
        `DV`.`StartDate` AS `StartMonth`,
        `DV`.`EndDate` AS `EndMonth`
    FROM
        `VW_Generic_Version` `DV`
    UNION ALL
    SELECT 
        `M`.`VersionName` AS `VersionName`,
        (`M`.`StartMonth` + INTERVAL 1 MONTH) AS `NextMonth`,
        `M`.`EndMonth` AS `EndMonth`
    FROM
        `months` `M`
    WHERE
        (`M`.`StartMonth` < `M`.`EndMonth`)
), 

`Group_Level1` AS (
    SELECT 
        `T1`.`Group_L1` AS `Group_L1`,
        MAX(`T3`.`Rate_L3`) AS `Rate_L3`
    FROM 
        (`Dim_L3` `T3`
    JOIN `Dim_L1` `T1` 
        ON (`T1`.`Code_L1` = `T3`.`Code_L3`))
    WHERE 
        (`T1`.`Group_L1` <> '')
    GROUP BY 
        `T1`.`Group_L1`
) 

SELECT DISTINCT 
    `c`.`Group_L1` AS `Profile`,
    (`c`.`Rate_L3` / 100) AS `RatePercent`,
    DATE_FORMAT(`m`.`StartMonth`, '%Y%m') AS `MonthFormatted`
FROM 
    (`Group_Level1` `c`
JOIN `months` `m`)
ORDER BY 
    `c`.`Group_L1`,
    `m`.`StartMonth`;
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
