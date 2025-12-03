-- Sample 038: Spatial Data Procedures
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Reporting
-- Complexity: Advanced
-- Features: GEOGRAPHY, GEOMETRY, STDistance, STIntersects, STBuffer, spatial indexes

-- Find locations within radius
CREATE PROCEDURE dbo.FindLocationsWithinRadius
    @Latitude FLOAT,
    @Longitude FLOAT,
    @RadiusKm FLOAT,
    @LocationType NVARCHAR(50) = NULL,
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SearchPoint GEOGRAPHY;
    DECLARE @RadiusMeters FLOAT = @RadiusKm * 1000;
    
    -- Create search point (SRID 4326 = WGS84)
    SET @SearchPoint = GEOGRAPHY::Point(@Latitude, @Longitude, 4326);
    
    SELECT TOP (@MaxResults)
        l.LocationID,
        l.LocationName,
        l.LocationType,
        l.Address,
        l.City,
        l.State,
        l.Latitude,
        l.Longitude,
        @SearchPoint.STDistance(l.GeoLocation) / 1000 AS DistanceKm,
        l.GeoLocation.STAsText() AS WKT
    FROM dbo.Locations l
    WHERE l.GeoLocation.STDistance(@SearchPoint) <= @RadiusMeters
      AND (@LocationType IS NULL OR l.LocationType = @LocationType)
    ORDER BY l.GeoLocation.STDistance(@SearchPoint);
END
GO

-- Find nearest N locations
CREATE PROCEDURE dbo.FindNearestLocations
    @Latitude FLOAT,
    @Longitude FLOAT,
    @Count INT = 10,
    @LocationType NVARCHAR(50) = NULL,
    @MaxDistanceKm FLOAT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SearchPoint GEOGRAPHY;
    SET @SearchPoint = GEOGRAPHY::Point(@Latitude, @Longitude, 4326);
    
    SELECT TOP (@Count)
        l.LocationID,
        l.LocationName,
        l.LocationType,
        l.Address,
        l.Latitude,
        l.Longitude,
        @SearchPoint.STDistance(l.GeoLocation) / 1000 AS DistanceKm
    FROM dbo.Locations l
    WHERE (@LocationType IS NULL OR l.LocationType = @LocationType)
      AND (@MaxDistanceKm IS NULL OR @SearchPoint.STDistance(l.GeoLocation) <= @MaxDistanceKm * 1000)
    ORDER BY @SearchPoint.STDistance(l.GeoLocation);
END
GO

-- Check if point is within polygon region
CREATE PROCEDURE dbo.CheckPointInRegion
    @Latitude FLOAT,
    @Longitude FLOAT,
    @RegionID INT = NULL,
    @RegionName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TestPoint GEOGRAPHY;
    SET @TestPoint = GEOGRAPHY::Point(@Latitude, @Longitude, 4326);
    
    SELECT 
        r.RegionID,
        r.RegionName,
        r.RegionType,
        CASE WHEN r.RegionBoundary.STIntersects(@TestPoint) = 1 
             THEN 'Inside' ELSE 'Outside' END AS PointStatus,
        r.RegionBoundary.STArea() / 1000000 AS AreaSqKm,
        @TestPoint.STDistance(r.RegionBoundary.STBoundary()) / 1000 AS DistanceFromBoundaryKm
    FROM dbo.Regions r
    WHERE (@RegionID IS NULL OR r.RegionID = @RegionID)
      AND (@RegionName IS NULL OR r.RegionName LIKE '%' + @RegionName + '%');
END
GO

-- Calculate route distance between locations
CREATE PROCEDURE dbo.CalculateRouteDistance
    @LocationIDs NVARCHAR(MAX),  -- Comma-separated list of location IDs in order
    @ReturnWaypoints BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Locations TABLE (
        Sequence INT,
        LocationID INT,
        GeoLocation GEOGRAPHY
    );
    
    -- Parse location IDs and get coordinates
    INSERT INTO @Locations (Sequence, LocationID, GeoLocation)
    SELECT 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
        CAST(value AS INT),
        l.GeoLocation
    FROM STRING_SPLIT(@LocationIDs, ',') s
    INNER JOIN dbo.Locations l ON l.LocationID = CAST(s.value AS INT);
    
    -- Calculate leg distances
    ;WITH Legs AS (
        SELECT 
            l1.Sequence AS FromSeq,
            l2.Sequence AS ToSeq,
            l1.LocationID AS FromLocationID,
            l2.LocationID AS ToLocationID,
            l1.GeoLocation.STDistance(l2.GeoLocation) / 1000 AS LegDistanceKm
        FROM @Locations l1
        INNER JOIN @Locations l2 ON l2.Sequence = l1.Sequence + 1
    )
    SELECT 
        FromSeq,
        ToSeq,
        FromLocationID,
        fl.LocationName AS FromLocation,
        ToLocationID,
        tl.LocationName AS ToLocation,
        LegDistanceKm
    FROM Legs lg
    INNER JOIN dbo.Locations fl ON lg.FromLocationID = fl.LocationID
    INNER JOIN dbo.Locations tl ON lg.ToLocationID = tl.LocationID
    ORDER BY FromSeq;
    
    -- Total distance
    SELECT 
        COUNT(*) AS NumberOfLegs,
        SUM(l1.GeoLocation.STDistance(l2.GeoLocation)) / 1000 AS TotalDistanceKm
    FROM @Locations l1
    INNER JOIN @Locations l2 ON l2.Sequence = l1.Sequence + 1;
END
GO

-- Find locations within polygon boundary
CREATE PROCEDURE dbo.FindLocationsInPolygon
    @PolygonWKT NVARCHAR(MAX),  -- Well-Known Text format polygon
    @LocationType NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SearchArea GEOGRAPHY;
    
    BEGIN TRY
        SET @SearchArea = GEOGRAPHY::STGeomFromText(@PolygonWKT, 4326);
    END TRY
    BEGIN CATCH
        RAISERROR('Invalid polygon WKT format', 16, 1);
        RETURN;
    END CATCH
    
    SELECT 
        l.LocationID,
        l.LocationName,
        l.LocationType,
        l.Address,
        l.City,
        l.State,
        l.Latitude,
        l.Longitude
    FROM dbo.Locations l
    WHERE @SearchArea.STIntersects(l.GeoLocation) = 1
      AND (@LocationType IS NULL OR l.LocationType = @LocationType)
    ORDER BY l.LocationName;
    
    -- Summary
    SELECT 
        COUNT(*) AS LocationsFound,
        @SearchArea.STArea() / 1000000 AS SearchAreaSqKm;
END
GO

-- Create spatial index recommendation
CREATE PROCEDURE dbo.AnalyzeSpatialIndexes
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Find tables with geography/geometry columns
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        c.name AS ColumnName,
        tp.name AS DataType,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM sys.spatial_indexes si 
                WHERE si.object_id = t.object_id
            ) THEN 'Has Spatial Index'
            ELSE 'No Spatial Index - Consider Creating'
        END AS IndexStatus
    FROM sys.columns c
    INNER JOIN sys.types tp ON c.user_type_id = tp.user_type_id
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE tp.name IN ('geography', 'geometry')
      AND (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName);
    
    -- Existing spatial indexes
    SELECT 
        s.name AS SchemaName,
        t.name AS TableName,
        si.name AS IndexName,
        si.type_desc AS IndexType,
        c.name AS ColumnName,
        sip.tessellation_scheme AS TessellationScheme,
        sip.cells_per_object AS CellsPerObject,
        sip.bounding_box_xmin, sip.bounding_box_ymin,
        sip.bounding_box_xmax, sip.bounding_box_ymax
    FROM sys.spatial_indexes si
    INNER JOIN sys.tables t ON si.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.index_columns ic ON si.object_id = ic.object_id AND si.index_id = ic.index_id
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    LEFT JOIN sys.spatial_index_tessellations sip ON si.object_id = sip.object_id AND si.index_id = sip.index_id
    WHERE (@SchemaName IS NULL OR s.name = @SchemaName)
      AND (@TableName IS NULL OR t.name = @TableName);
END
GO
