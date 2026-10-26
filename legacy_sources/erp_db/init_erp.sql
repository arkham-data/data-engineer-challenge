-- =============================================================================
-- ARKHAM PLATFORM - LEGACY ERP & INVENTORY LEDGER DUMP
-- =============================================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS arkham_erp;
SET search_path TO arkham_erp, public;

CREATE TABLE arkham_erp.tenants (
    tenant_id VARCHAR(32) PRIMARY KEY,
    tenant_slug VARCHAR(64) NOT NULL UNIQUE,
    company_name VARCHAR(128) NOT NULL,
    tier VARCHAR(32) NOT NULL DEFAULT 'ENTERPRISE',
    workspace_env VARCHAR(24) NOT NULL DEFAULT 'PRODUCTION',
    region VARCHAR(16) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE arkham_erp.locations (
    location_id VARCHAR(48) PRIMARY KEY,
    tenant_id VARCHAR(32) NOT NULL REFERENCES arkham_erp.tenants(tenant_id),
    location_type VARCHAR(24) NOT NULL,
    parent_supply_node_id VARCHAR(48),
    banner_name VARCHAR(128) NOT NULL,
    country_code CHAR(2) NOT NULL,
    postal_code VARCHAR(16),
    operating_status VARCHAR(24) NOT NULL DEFAULT 'OPEN',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE arkham_erp.products (
    product_id VARCHAR(48) PRIMARY KEY,
    tenant_id VARCHAR(32) NOT NULL REFERENCES arkham_erp.tenants(tenant_id),
    internal_sku VARCHAR(64) NOT NULL,
    gtin_barcode VARCHAR(32) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    category_code VARCHAR(64) NOT NULL,
    primary_supplier_id VARCHAR(48),
    substitute_product_id VARCHAR(48),
    unit_cost_cents INTEGER NOT NULL,
    retail_price_cents INTEGER NOT NULL,
    lowcode_attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_discontinued BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE arkham_erp.inventory_ledger (
    ledger_entry_id BIGINT PRIMARY KEY,
    tenant_id VARCHAR(32) NOT NULL,
    location_id VARCHAR(48) NOT NULL,
    product_id VARCHAR(48) NOT NULL,
    movement_type VARCHAR(32) NOT NULL,
    quantity_delta INTEGER NOT NULL,
    entry_status VARCHAR(24) NOT NULL DEFAULT 'POSTED_00',
    reference_doc_id VARCHAR(64),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    event_occurred_at TIMESTAMPTZ NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL,
    lowcode_workflow_meta JSONB
);

CREATE INDEX idx_inv_ledger_ingested ON arkham_erp.inventory_ledger(ingested_at);
CREATE INDEX idx_inv_ledger_tenant ON arkham_erp.inventory_ledger(tenant_id);
CREATE INDEX idx_products_gtin ON arkham_erp.products(gtin_barcode);

INSERT INTO arkham_erp.tenants (tenant_id, tenant_slug, company_name, tier, workspace_env, region, is_active, created_at, updated_at)
VALUES
    ('TENANT_CPG_001', 'aurora-foods-global', 'Aurora Consumer Foods Corp', 'ENTERPRISE', 'PRODUCTION', 'NA-EAST', TRUE, '2024-01-10 08:00:00+00', '2026-09-01 12:00:00+00'),
    ('TENANT_CPG_002', 'verde-beverage-co', 'Verde Beverage & Snacks Ltd', 'ENTERPRISE', 'PRODUCTION', 'LATAM', TRUE, '2024-03-15 08:00:00+00', '2026-09-05 15:30:00+00'),
    ('TENANT_RTL_003', 'meridian-grocers', 'Meridian Supermarkets Group', 'ENTERPRISE', 'PRODUCTION', 'EU-WEST', TRUE, '2024-06-01 08:00:00+00', '2026-09-10 09:15:00+00'),
    ('TENANT_RTL_004', 'nova-mart-express', 'NovaMart Convenience Holdings', 'GROWTH', 'PRODUCTION', 'NA-WEST', TRUE, '2025-01-20 08:00:00+00', '2026-09-12 18:45:00+00'),
    ('TENANT_DEMO_000', 'arkham-lowcode-sandbox', 'Arkham Internal LowCode Sandbox', 'INTERNAL', 'SANDBOX_LOADTEST', 'GLOBAL', TRUE, '2023-11-01 00:00:00+00', '2026-09-15 00:00:00+00');

INSERT INTO arkham_erp.locations (location_id, tenant_id, location_type, parent_supply_node_id, banner_name, country_code, postal_code, operating_status, updated_at)
VALUES
    ('LOC_UNASSIGNED_000', 'TENANT_DEMO_000', 'VIRTUAL_POOL', NULL, 'Unassigned Legacy Import Buffer', 'US', '00000', 'BUFFER', '2026-09-01 00:00:00+00'),
    ('PLANT_NA_01', 'TENANT_CPG_001', 'SUPPLIER_PLANT', NULL, 'Aurora Midwest Bottling & Milling', 'US', '60601', 'OPEN', '2026-09-01 00:00:00+00'),
    ('PLANT_LA_01', 'TENANT_CPG_002', 'SUPPLIER_PLANT', NULL, 'Verde Monterrey Roastery & Pack', 'MX', '64000', 'OPEN', '2026-09-01 00:00:00+00'),
    ('PLANT_EU_01', 'TENANT_RTL_003', 'SUPPLIER_PLANT', NULL, 'EuroCoop Central Commissary', 'NL', '3011', 'OPEN', '2026-09-01 00:00:00+00'),
    ('DC_CENTRAL_HUB_01', 'TENANT_CPG_001', 'REGIONAL_DC', 'PLANT_NA_01', 'Arkham Shared Logistics Hub North', 'US', '07102', 'OPEN', '2026-09-02 00:00:00+00'),
    ('DC_SOUTH_HUB_02', 'TENANT_CPG_002', 'REGIONAL_DC', 'PLANT_LA_01', 'Verde Cross-Border Logistics Hub', 'MX', '32000', 'OPEN', '2026-09-02 00:00:00+00'),
    ('DC_EU_HUB_03', 'TENANT_RTL_003', 'REGIONAL_DC', 'PLANT_EU_01', 'Meridian Benelux Fulfillment DC', 'BE', '2000', 'OPEN', '2026-09-02 00:00:00+00'),
    ('DC_WEST_HUB_04', 'TENANT_RTL_004', 'REGIONAL_DC', 'DC_CENTRAL_HUB_01', 'NovaMart Pacific Redistribution', 'US', '90001', 'OPEN', '2026-09-02 00:00:00+00');

INSERT INTO arkham_erp.locations (location_id, tenant_id, location_type, parent_supply_node_id, banner_name, country_code, postal_code, operating_status, updated_at)
SELECT
    'STORE_' || lpad(gs::text, 4, '0'),
    CASE (gs % 4)
        WHEN 0 THEN 'TENANT_CPG_001'
        WHEN 1 THEN 'TENANT_CPG_002'
        WHEN 2 THEN 'TENANT_RTL_003'
        ELSE 'TENANT_RTL_004'
    END,
    'RETAIL_STORE',
    CASE
        WHEN gs % 5 = 0 THEN 'DC_CENTRAL_HUB_01'
        WHEN gs % 4 = 0 THEN 'DC_CENTRAL_HUB_01'
        WHEN gs % 4 = 1 THEN 'DC_SOUTH_HUB_02'
        WHEN gs % 4 = 2 THEN 'DC_EU_HUB_03'
        ELSE 'DC_WEST_HUB_04'
    END,
    'Banner Store #' || gs,
    CASE (gs % 4) WHEN 1 THEN 'MX' WHEN 2 THEN 'NL' ELSE 'US' END,
    lpad((10000 + gs * 37)::text, 5, '0'),
    CASE WHEN gs % 29 = 0 THEN 'RENOVATION_HOLD' ELSE 'OPEN' END,
    TIMESTAMPTZ '2026-09-01 00:00:00+00' + (gs || ' minutes')::interval
FROM generate_series(1, 120) AS gs;

DO $$
DECLARE
    real_gtins TEXT[] := ARRAY[
        '3017620422003',
        '03017620422003',
        ' 5449000000996 ',
        '7622210449283',
        '00049000028904',
        '8076809513753',
        '3228857000166',
        '7613034626844',
        '3046920022651',
        '5000112637922',
        '3168930010265',
        '8715700407760',
        '0028400090896',
        '028400090896',
        '4008400404127',
        '5410041001204',
        '3033710065967',
        '7622300336738',
        '3274080005003',
        '8000500037560'
    ];
    categories TEXT[] := ARRAY['BEVERAGES', 'SNACKS_CONFECTIONERY', 'PANTRY_STAPLES', 'BREAKFAST_CEREAL', 'CONDIMENTS'];
    i INT;
    t_id VARCHAR(32);
    raw_code TEXT;
    formatted_code TEXT;
    sub_prod VARCHAR(48);
    lc_json JSONB;
BEGIN
    FOR i IN 1..200 LOOP
        t_id := CASE (i % 4)
            WHEN 0 THEN 'TENANT_CPG_001'
            WHEN 1 THEN 'TENANT_CPG_002'
            WHEN 2 THEN 'TENANT_RTL_003'
            ELSE 'TENANT_RTL_004'
        END;

        raw_code := real_gtins[1 + ((i - 1) % array_length(real_gtins, 1))];
        IF i % 7 = 0 THEN
            formatted_code := '00' || btrim(raw_code);
        ELSIF i % 11 = 0 THEN
            formatted_code := ' ' || raw_code || ' ';
        ELSIF i % 13 = 0 THEN
            formatted_code := 'GTIN:' || btrim(raw_code);
        ELSE
            formatted_code := raw_code;
        END IF;

        IF i > 1 THEN
            sub_prod := 'PROD_' || lpad(((i % 20) + 1)::text, 4, '0');
            IF sub_prod = ('PROD_' || lpad(i::text, 4, '0')) THEN
                sub_prod := NULL;
            END IF;
        ELSE
            sub_prod := NULL;
        END IF;

        IF t_id = 'TENANT_CPG_001' THEN
            lc_json := jsonb_build_object('pack_size', 12, 'uom', 'EA', 'shelf_life_days', 180, 'promo_eligible', true);
        ELSIF t_id = 'TENANT_CPG_002' THEN
            lc_json := jsonb_build_object('pack_size', '12x500ml', 'uom', 'CASE', 'shelf_life_days', '180d', 'promo_eligible', 'yes');
        ELSIF t_id = 'TENANT_RTL_003' THEN
            lc_json := jsonb_build_object('pack_size', jsonb_build_object('inner', 6, 'outer', 24), 'uom', 'PALLET_LAYER', 'temp_zone', 'AMBIENT');
        ELSE
            lc_json := jsonb_build_object('pack_size', NULL, 'custom_tags', jsonb_build_array('fast-mover', 'endcap'));
        END IF;

        INSERT INTO arkham_erp.products (
            product_id, tenant_id, internal_sku, gtin_barcode, product_name,
            category_code, primary_supplier_id, substitute_product_id,
            unit_cost_cents, retail_price_cents, lowcode_attributes, is_discontinued, updated_at
        ) VALUES (
            'PROD_' || lpad(i::text, 4, '0'),
            t_id,
            'SKU-' || substr(t_id, 8, 3) || '-' || lpad(i::text, 5, '0'),
            formatted_code,
            'Arkham CPG Item #' || i || ' (' || categories[1 + (i % 5)] || ')',
            categories[1 + (i % 5)],
            CASE (i % 3) WHEN 0 THEN 'PLANT_NA_01' WHEN 1 THEN 'PLANT_LA_01' ELSE 'PLANT_EU_01' END,
            sub_prod,
            150 + (i * 7) % 850,
            299 + (i * 11) % 1400,
            lc_json,
            (i % 37 = 0),
            TIMESTAMPTZ '2026-09-01 00:00:00+00' + (i || ' hours')::interval
        );
    END LOOP;
END $$;

INSERT INTO arkham_erp.inventory_ledger (
    ledger_entry_id,
    tenant_id,
    location_id,
    product_id,
    movement_type,
    quantity_delta,
    entry_status,
    reference_doc_id,
    is_deleted,
    event_occurred_at,
    ingested_at,
    lowcode_workflow_meta
)
SELECT
    gs AS ledger_entry_id,
    CASE
        WHEN gs % 10 < 6 THEN 'TENANT_DEMO_000'
        WHEN gs % 10 = 6 THEN 'TENANT_CPG_001'
        WHEN gs % 10 = 7 THEN 'TENANT_CPG_002'
        WHEN gs % 10 = 8 THEN 'TENANT_RTL_003'
        ELSE 'TENANT_RTL_004'
    END AS tenant_id,
    CASE
        WHEN gs % 10 < 6 THEN 'LOC_UNASSIGNED_000'
        WHEN gs % 25 = 0 THEN 'LOC_ORPHAN_' || (gs % 7)
        ELSE 'STORE_' || lpad(((gs % 120) + 1)::text, 4, '0')
    END AS location_id,
    'PROD_' || lpad(((gs % 200) + 1)::text, 4, '0') AS product_id,
    CASE (gs % 5)
        WHEN 0 THEN 'RECEIPT'
        WHEN 1 THEN 'REPLENISHMENT_OUT'
        WHEN 2 THEN 'STORE_ALLOCATION'
        WHEN 3 THEN 'SHRINKAGE'
        ELSE 'ADJUSTMENT'
    END AS movement_type,
    CASE
        WHEN gs % 5 IN (0, 2) THEN 10 + (gs % 90)
        ELSE -1 * (1 + (gs % 25))
    END AS quantity_delta,
    CASE
        WHEN gs % 19 = 0 THEN 'VOID_CANCELLED_99'
        WHEN gs % 23 = 0 THEN 'PENDING_APPROVAL'
        WHEN gs % 41 = 0 THEN 'DUPLICATE_REPLAY'
        ELSE 'POSTED_00'
    END AS entry_status,
    CASE
        WHEN gs > 150000 AND gs % 37 = 0 THEN 'DOC-ERP-' || lpad((gs - 74000)::text, 8, '0')
        ELSE 'DOC-ERP-' || lpad(gs::text, 8, '0')
    END AS reference_doc_id,
    FALSE AS is_deleted,
    CASE
        WHEN gs <= 100000 THEN
            TIMESTAMPTZ '2026-10-01 00:00:00+00' + ((gs % 432000) || ' seconds')::interval
        WHEN gs <= 180000 AND gs % 9 = 0 THEN
            TIMESTAMPTZ '2026-10-02 04:00:00+00' + ((gs % 172800) || ' seconds')::interval
        WHEN gs <= 180000 THEN
            TIMESTAMPTZ '2026-10-06 00:00:00+00' + ((gs % 432000) || ' seconds')::interval
        ELSE
            TIMESTAMPTZ '2026-10-11 00:00:00+00' + ((gs % 432000) || ' seconds')::interval
    END AS event_occurred_at,
    CASE
        WHEN gs <= 100000 THEN
            TIMESTAMPTZ '2026-10-01 00:05:00+00' + ((gs % 432000) || ' seconds')::interval
        WHEN gs <= 180000 THEN
            TIMESTAMPTZ '2026-10-06 00:05:00+00' + ((gs % 432000) || ' seconds')::interval
        ELSE
            TIMESTAMPTZ '2026-10-11 00:05:00+00' + ((gs % 432000) || ' seconds')::interval
    END AS ingested_at,
    jsonb_build_object(
        'workflow_run_id', 'wf_' || (gs % 5000),
        'schema_version', CASE WHEN gs > 180000 THEN '2.1-lowcode' ELSE '1.0' END,
        'operator_notes', CASE WHEN gs % 10 < 6 THEN repeat('SANDBOX_TRACE_PAYLOAD_', 12) ELSE 'std_sync' END
    ) AS lowcode_workflow_meta
FROM generate_series(1, 250000) AS gs;

ANALYZE arkham_erp.tenants;
ANALYZE arkham_erp.locations;
ANALYZE arkham_erp.products;
ANALYZE arkham_erp.inventory_ledger;
