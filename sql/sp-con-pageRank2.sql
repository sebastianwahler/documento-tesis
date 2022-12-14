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
delete from dbo.tempPersonas
/*
create table tempPersonas
(
	value int, 
	id int ,
	label varchar (1000),
	fallecido bit,
	documento varchar (20),
	grupo int
)
*/
if (@IdTipoDelito <> 0 OR @IdTituloDelito <> 0 OR @IdCapituloDelito <> 0 ) -- elegió algun tipo/capitulo/titulo delito, hacer inner y where de delitos
begin 
	insert into tempPersonas
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

	insert into tempPersonas
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
delete from dbo.tempEnlaces
/*
create table tempEnlaces 
(
value int , 
	IDfrom int ,
	IDTo int , 
	DescripcionDesde varchar (1000) , DescripcionHasta varchar (1000)
	, grupo int
)
*/
insert into tempEnlaces 
select value = e.Valor, 
	IDfrom = idnododesde,
	IDTo = idnodoHasta, E.DescripcionHasta, E.DescripcionDesde -- ESTÁ MAL EN LA TABLA redgpEnlace!!!!!!!!!!!!!!
	, Grupo = TP.id
--from tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idnododesde or TP.id =  E.idNodoHasta)
from tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idnododesde)

insert into tempEnlaces 
select value = e.Valor, 
	IDfrom = idnododesde,
	IDTo = idnodoHasta, E.DescripcionHasta, E.DescripcionDesde -- ESTÁ MAL EN LA TABLA redgpEnlace!!!!!!!!!!!!!!
	, Grupo = TP.id
from tempPersonas TP inner join redgpEnlace E on (TP.id =  E.idNodoHasta)
Where 
	(idnododesde not in (select IDfrom from tempEnlaces where IDfrom = idnododesde AND IDTo = IdNodoHasta))
/*
	AND idnodoHasta not in (select IDTo from tempEnlaces where IDTo = idnodoHasta))
	AND
	(idnododesde not in (select IDfrom from tempEnlaces where IDfrom = idnododesde)
	AND idnodoHasta in (select IDTo from tempEnlaces where IDTo = idnodoHasta))
	*/

--*************************************************************
-- GRUPO DE PERTENENCIA DE CADA NODO
--*************************************************************
if (@mostrarGrupo = 1) -- para cada nodo, mostrar su nodo enlace, muestra el grupo de pertenencia
begin 
	insert into tempPersonas
	select value = valor, 
		id = idNodo,
		label = descripcion , Fallecido = P.Fallecido, documento = P.NroDocumento --  0 ,  '' --
		,grupo = 0-- TE.IDfrom
	from redgpNodo N 
		inner join tempEnlaces TE on (N.idnodo =  TE.IDTo or N.idnodo =  TE.IDfrom)
		inner join Persona P on N.IdNodo = P.IdPersona
/*-----------------------------------------------------------------------------*/
	Where N.idnodo not in (select Id from tempPersonas where id = N.IdNodo)

end

update tempEnlaces
set IDfrom = IDTo, IDTo = IDfrom, DescripcionDesde = DescripcionHasta, DescripcionHasta = DescripcionDesde
where grupo = IDTo

----********************************************************************
---- PAGE RANK
----********************************************************************
/*
drop table Nodes
CREATE TABLE Nodes
(NodeId int not null
,NodeWeight decimal(10,5)
,NodeCount int not null default(0)
,HasConverged bit not null default(0)
,constraint NodesPK primary key clustered (NodeId)
)
go
drop table Edges
CREATE TABLE Edges
(SourceNodeId int not null
,TargetNodeId int not null
,constraint EdgesPK primary key clustered (SourceNodeId, TargetNodeId)
)
go
*/
delete from dbo.Nodes
delete from dbo.Edges


INSERT INTO dbo.Nodes
(NodeId
,NodeWeight
,HasConverged)
select id, (value/100), 0 from tempPersonas

INSERT INTO dbo.Edges
(SourceNodeId
,TargetNodeId)
select distinct IdFrom, IDTo from tempEnlaces

-- Running PageRank
declare @DampingFactor decimal(3,2) = 0.85
	,@MarginOfError decimal(10,5) = 0.001
	,@TotalNodeCount int

select @TotalNodeCount = count(*)
from dbo.Nodes

update n
set n.NodeCount = isnull(x.TargetNodeCount,@TotalNodeCount) --store the number of edges each node has pointing away from it.
	-- if a node has 0 edges going away (it's a sink), then its number is the total number of edges in the system.
from dbo.Nodes n
left outer join
(
	select SourceNodeID,
		TargetNodeCount = count(*)
	from dbo.Edges
	group by SourceNodeId
) as x
on x.SourceNodeID = n.NodeId

-- select * from dbo.Nodes


	set @DampingFactor = 0.85
	set @MarginOfError = 0.001
	declare @IterationCount int = 1

select @TotalNodeCount = count(*)
from dbo.Nodes

WHILE EXISTS
(
	SELECT *
	FROM dbo.Nodes
	WHERE HasConverged = 0
)
BEGIN

	UPDATE n
	SET 
	NodeWeight = 1.0 - @DampingFactor + isnull(x.TransferredNodeWeight, 0.0)
	,HasConverged = case when abs(n.NodeWeight - (1.0 - @DampingFactor + isnull(x.TransferredNodeWeight, 0.0))) < @MarginOfError then 1 else 0 end
	FROM Nodes n
	LEFT OUTER JOIN
	(
		-- Compute the PageRank each target node by the sum
		-- of the nodes' weights that point to it.
		SELECT
			e.TargetNodeId
			,TransferredNodeWeight = sum(n.NodeWeight / n.NodeCount) * @DampingFactor
		FROM Nodes n
		INNER JOIN Edges e
		  ON n.NodeId = e.SourceNodeId
		WHERE e.SourceNodeId <> e.TargetNodeId --self references are ignored
		GROUP BY e.TargetNodeId
	) as x
	on x.TargetNodeId = n.NodeId
/*
	select
		@IterationCount as IterationCount
		,*
	from Nodes
*/
	set @IterationCount += 1
END

----********************************************************************
---- Ya estan generadas las tabla, devolver los datos según parametros
----********************************************************************
/*
SELECT distinct * FROM #PageRank pr
	inner  join tempPersonas p ON p.id = pr.id 
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
	,RANK = pr.NodeWeight-- = RANK + ((1 - @dampingFactor) / E.value)
from tempPersonas p
	left  join Nodes pr ON p.id = pr.NodeId 
	--left  join #PageRank pr ON p.id = pr.id 
	--left join #Edge E ON E.src = p.id
order by rank desc

select distinct * from tempEnlaces
--where ( IDfrom not in (145262,132306,132310,32782,123109)
--	OR IDTo not in (145262,132306,132310,32782,123109) )
--where DescripcionHasta like '%schul%' or  DescripcionDesde like '%schul%'
--where IDfrom = 123479 or IDTo = 123479
order by DescripcionDesde

select distinct Grupo from tempEnlaces 

--select distinct * from #Edge
END


