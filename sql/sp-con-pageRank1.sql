USE [Coiron_desa]
GO
/****** Object:  StoredProcedure [dbo].[pRedGrupoPertenenciaTesisListar]    Script Date: 2/7/2022 17:38:08 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[pRedGrupoPertenenciaTesisListar] 
		@top int,
		@mostrarGrupo bit,
		@mostrarFallecidos bit,
		@mostrarMenores bit,
		@mostrarJuridicas bit,
		@IdTituloDelito SMALLINT,
		@IdCapituloDelito SMALLINT,
		@IdTipoDelito SMALLINT,
		@listaPersonas varchar(200)
AS

begin
--*************************************************************
-- NODOS
--*************************************************************
declare @where varchar (5000) 
declare @from varchar (5000)

set @where = ''	
set @from =  ''
create table #tempPersonasSeleccionadas
(
	valor int, 
	idNodo int ,
	descripcion varchar (1000)

)

if (@top < 0) -- mostrar red de personas 
begin 
	select @top = COUNT (*) from RedGPNodo
	if (@listaPersonas != '' )  --seleccionó personas
		set @where = ' where IdNodo in (' + @listaPersonas + ')';
	insert into #tempPersonasSeleccionadas
	execute ('SELECT  valor, 
						 idNodo,
						 descripcion
						FROM redgpNodo N  ' 
						+  @where + ' order by valor DESC');

end
else
begin 
	if (@top = 0 ) -- todos los nodos sin top, devolver todos los nodos
		select @top = COUNT (*) from RedGPNodo
	insert into #tempPersonasSeleccionadas
	SELECT   valor,  idNodo,  descripcion
			FROM redgpNodo N 
			order by Valor DESC
end 

create table #tempPersonas
(
	value int, 
	id int ,
	label varchar (1000),
	fallecido bit,
	documento varchar (20),
	grupo int
)

if (@IdTipoDelito <> 0 OR @IdTituloDelito <> 0 OR @IdCapituloDelito <> 0 ) -- elegió algun tipo/capitulo/titulo delito, hacer inner y where de delitos
begin 
	insert into #tempPersonas
	SELECT top (@top)
		value = n.valor , 
		IdNacionalidad = n.idNodo,
		label = n.descripcion  , P.Fallecido, documento= p.NroDocumento
	FROM #tempPersonasSeleccionadas N inner join Persona P on N.IdNodo = P.IdPersona 
		inner join RedGPNodoRelacionEnlace NRE on N.idnodo =  NRE.idnodo
		LEFT JOIN Delito D ON D.idCaso = NRE.idrelacion
		LEFT JOIN TipoDelito TD ON TD.idTipoDelito = D.IdTipoDelito
		LEFT JOIN TipoDelitoCapitulo CD ON TD.idcapitulo = CD.idCapitulo
		LEFT JOIN TipoDelitoTitulo UD ON CD.idTitulo = UD.idTitulo 
		where ((@mostrarFallecidos = 0 AND P.Fallecido = 0 ) OR @mostrarFallecidos = 1)
		AND ((@mostrarJuridicas = 0 AND P.PersonaFisica = 1) OR (@mostrarJuridicas = 1 ))
		AND ((@mostrarMenores = 0 AND (dbo.fEsMenor (p.FechaNacimiento, p.edad2, p.menor, p.sindatosedad,getdate ()) = 0)) or @mostrarMenores = 1)
			AND (
			(@IdTipoDelito < 0 AND TD.descripcion is null) OR
			(D.IdTipoDelito = @IdTipoDelito ) OR
			(@IdTipoDelito = 0)
		)
	AND 	(CD.IdCapitulo  = @IdCapituloDelito OR @IdCapituloDelito = 0)
	AND 	(UD.IdTitulo  = @IdTituloDelito OR @IdTituloDelito = 0)

	order by valor DESC

end 
else -- si no eligio delito, no hacer inner con caso para no bajar performance
begin 

	insert into #tempPersonas
	SELECT top (@top)
		value = valor , 
		id = idNodo,
		label = descripcion  , Fallecido = P.Fallecido, documento = P.NroDocumento
		,grupo = idNodo 
	FROM #tempPersonasSeleccionadas N inner join Persona P on N.IdNodo = P.IdPersona 
	where ((@mostrarFallecidos = 0 AND P.Fallecido = 0 ) OR @mostrarFallecidos = 1)
		AND ((@mostrarJuridicas = 0 AND P.PersonaFisica = 1) OR (@mostrarJuridicas = 1 ))
		AND ((@mostrarMenores = 0 AND (dbo.fEsMenor (p.FechaNacimiento, p.edad2, p.menor, p.sindatosedad,getdate ()) = 0)) or @mostrarMenores = 1)

	order by valor DESC
end 
--*************************************************************
-- ENLACES
--*************************************************************
create table #tempEnlaces 
(
value int , 
	IDfrom int ,
	IDTo int , 
	DescripcionDesde varchar (1000) , DescripcionHasta varchar (1000)
	, grupo int
)

insert into #tempEnlaces 
select value = e.Valor, 
	IDfrom = idnododesde,
	IDTo = idnodoHasta, E.DescripcionHasta, E.DescripcionDesde -- ESTÁ MAL EN LA TABLA redgpEnlace!!!!!!!!!!!!!!
	, Grupo = TP.id
--from #tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idnododesde or TP.id =  E.idNodoHasta)
from #tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idnododesde)

insert into #tempEnlaces 
select value = e.Valor, 
	IDfrom = idnododesde,
	IDTo = idnodoHasta, E.DescripcionHasta, E.DescripcionDesde -- ESTÁ MAL EN LA TABLA redgpEnlace!!!!!!!!!!!!!!
	, Grupo = TP.id
from #tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idNodoHasta)
Where 
	(idnododesde not in (select IDfrom from #tempEnlaces where IDfrom = idnododesde AND IDTo = IdNodoHasta))
/*
	AND idnodoHasta not in (select IDTo from #tempEnlaces where IDTo = idnodoHasta))
	AND
	(idnododesde not in (select IDfrom from #tempEnlaces where IDfrom = idnododesde)
	AND idnodoHasta in (select IDTo from #tempEnlaces where IDTo = idnodoHasta))
	*/

--*************************************************************
-- GRUPO DE PERTENENCIA DE CADA NODO
--*************************************************************
if (@mostrarGrupo = 1) -- para cada nodo, mostrar su nodo enlace, muestra el grupo de pertenencia
begin 
	insert into #tempPersonas
	select value = valor, 
		id = idNodo,
		label = descripcion , Fallecido = P.Fallecido, documento = P.NroDocumento --  0 ,  '' --
		,grupo = 0-- TE.IDfrom
	from redgpNodo N 
		inner join #tempEnlaces TE on (N.idnodo =  TE.IDTo or N.idnodo =  TE.IDfrom)
		inner join Persona P on N.IdNodo = P.IdPersona
/*-----------------------------------------------------------------------------*/
	Where N.idnodo not in (select Id from #tempPersonas where id = N.IdNodo)

end

update #tempEnlaces
set IDfrom = IDTo, IDTo = IDfrom, DescripcionDesde = DescripcionHasta, DescripcionHasta = DescripcionDesde
where grupo = IDTo

----********************************************************************
---- PAGE RANK
----********************************************************************

CREATE TABLE #Node(id int PRIMARY KEY)
CREATE TABLE #Edge(src int,dst int, value int, PRIMARY KEY (src, dst))
CREATE TABLE #OutDegree(id int PRIMARY KEY, degree int)
CREATE TABLE #PageRank(id int PRIMARY KEY, rank float)
CREATE TABLE #TmpRank(id int PRIMARY KEY, rank float)

--delete all records
DELETE FROM #Node
DELETE FROM #Edge
DELETE FROM #OutDegree
DELETE FROM #PageRank
DELETE FROM #TmpRank

INSERT INTO #Node
select distinct id from #tempPersonas

INSERT INTO #Edge
select distinct IdFrom, IDTo, value 
from #tempEnlaces
--Para quedarme con las relaciones sólo de los nodos "elegidos"
where IDTo in (select distinct id from #Node N where N.id = IDTo)

INSERT INTO #Edge
select distinct IdTo, IDFrom, value 
from #tempEnlaces te
where (te.IDfrom) in (select src from #Edge where src = te.IDfrom)
--Para quedarme con las relaciones sólo de los nodos "elegidos"
AND IDTo in (select distinct id from #Node N where N.id = IDTo)

--compute out-degree
INSERT INTO #OutDegree
SELECT #Node.id, COUNT(#Edge.src) --Count(Edge.src) instead of Count(*) for count no out-degree edge
FROM #Node LEFT OUTER JOIN #Edge
ON #Node.id = #Edge.src
GROUP BY #Node.id

--WARN: There's no special process for node with out-degree, This may cause wrong result
--      Please to make sure every node in graph has out-degree

DECLARE @dampingFactor float = 0.85
DECLARE @Node_Num int
SELECT @Node_Num = COUNT(*) FROM #Node
DECLARE @Edge_Num int
SELECT @Edge_Num = SUM(e.value)  FROM #Edge e

--PageRank Init Value
INSERT INTO #PageRank
SELECT #Node.id, rank = ((1 - @dampingFactor) / @Node_Num)
FROM #Node 
INNER JOIN #OutDegree ON #Node.id = #OutDegree.id
--left JOIN #Edge ON #Node.id = #Edge.src

DECLARE @Iteration int = 0

WHILE @Iteration < 50
BEGIN
--Iteration Style
    SET @Iteration = @Iteration + 1

    INSERT INTO #TmpRank
    SELECT #Edge.dst, rank = ((1 - @dampingFactor) / @Node_Num) + (@dampingFactor * SUM(#PageRank.rank / #OutDegree.degree))
    FROM #PageRank
    INNER JOIN #Edge ON #PageRank.id = #Edge.src
    INNER JOIN #OutDegree ON #PageRank.id = #OutDegree.id
    GROUP BY #Edge.dst

    DELETE FROM #PageRank
    INSERT INTO #PageRank
    SELECT * FROM #TmpRank
    DELETE FROM #TmpRank
END



----********************************************************************
---- Ya estan generadas las tabla, devolver los datos según parametros
----********************************************************************
/*
SELECT distinct * FROM #PageRank pr
	inner  join #tempPersonas p ON p.id = pr.id 
order by rank desc
*/
--select * from #Node
--select * from #Edge

select distinct
	p.id,
	p.value,
	label,
	fallecido,
	documento,
	grupo
	,RANK-- = RANK + ((1 - @dampingFactor) / E.value)
from #tempPersonas p
	left  join #PageRank pr ON p.id = pr.id 
	--left join #Edge E ON E.src = p.id
order by rank desc

select distinct * from #tempEnlaces
--where ( IDfrom not in (145262,132306,132310,32782,123109)
--	OR IDTo not in (145262,132306,132310,32782,123109) )
--where DescripcionHasta like '%schul%' or  DescripcionDesde like '%schul%'
--where IDfrom = 123479 or IDTo = 123479
order by DescripcionDesde

select distinct Grupo from #tempEnlaces 

select distinct * from #Edge

END

