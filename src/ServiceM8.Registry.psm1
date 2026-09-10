<#
    ServiceM8.Registry
    The single source of truth for every ServiceM8 resource this wrapper knows about.

    Each resource drives generic CRUD generation:
      - Name      : friendly resource name (PascalCase), used in cmdlet names.
      - Path      : singular API path (no extension), e.g. 'job' -> '/job.json'.
      - ReadScope : scope required to read (list / retrieve).
      - WriteScope: scope required to create / update.
      - DeleteScope: scope required to delete (defaults to WriteScope).

    Endpoint conventions (verified against developer.servicem8.com):
      List        : GET  /<path>.json
      Retrieve    : GET  /<path>/<uuid>.json
      Create      : POST /<path>.json  (x-record-uuid header on success)
      Update      : POST /<path>/<uuid>.json
      Delete      : DELETE /<path>/<uuid>.json  (sets active=0)

    Add a new resource here and the generic CRUD + typed cmdlets follow automatically.
#>

Set-StrictMode -Version Latest

function Get-Sm8Registry {
    <#
    .SYNOPSIS
        Return the resource registry as an array of PSCustomObjects.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    [array] $resources = @(
        # Core
        [pscustomobject]@{ Name='Job';                 Path='job';                 ReadScope='read_jobs';                 WriteScope='create_jobs';     DeleteScope='manage_jobs' }
        [pscustomobject]@{ Name='Company';             Path='company';             ReadScope='read_customers';          WriteScope='manage_customers';DeleteScope='manage_customers' }
        [pscustomobject]@{ Name='Client';             Path='company';             ReadScope='read_customers';          WriteScope='manage_customers';DeleteScope='manage_customers' }
        [pscustomobject]@{ Name='Material';            Path='material';            ReadScope='read_inventory';          WriteScope='create_inventory';DeleteScope='manage_inventory' }
        [pscustomobject]@{ Name='Attachment';          Path='attachment';          ReadScope='read_attachments';        WriteScope='manage_attachments';DeleteScope='manage_attachments' }

        # Scheduling / dispatch
        [pscustomobject]@{ Name='Availability';        Path='availability';        ReadScope='read_schedule';           WriteScope='manage_schedule';DeleteScope='manage_schedule' }
        [pscustomobject]@{ Name='JobActivity';         Path='jobactivity';         ReadScope='read_schedule';           WriteScope='manage_schedule';DeleteScope='manage_schedule' }
        [pscustomobject]@{ Name='JobAllocation';       Path='joballocation';       ReadScope='read_schedule';           WriteScope='manage_schedule';DeleteScope='manage_schedule' }
        [pscustomobject]@{ Name='AllocationWindow';    Path='allocationwindow';    ReadScope='read_schedule';           WriteScope='manage_schedule';DeleteScope='manage_schedule' }

        # Jobs related
        [pscustomobject]@{ Name='JobTemplate';         Path='jobtemplate';         ReadScope='read_jobs';               WriteScope='create_jobs';     DeleteScope='manage_jobs' }
        [pscustomobject]@{ Name='JobChecklist';        Path='jobchecklist';        ReadScope='read_job_checklists';     WriteScope='manage_job_checklists';DeleteScope='manage_job_checklists' }
        [pscustomobject]@{ Name='JobContact';          Path='jobcontact';          ReadScope='read_job_contacts';       WriteScope='manage_job_contacts';DeleteScope='manage_job_contacts' }
        [pscustomobject]@{ Name='JobMaterial';         Path='jobmaterial';         ReadScope='read_job_materials';      WriteScope='manage_job_materials';DeleteScope='manage_job_materials' }
        [pscustomobject]@{ Name='JobPayment';          Path='jobpayment';          ReadScope='read_job_payments';       WriteScope='manage_job_payments';DeleteScope='manage_job_payments' }
        [pscustomobject]@{ Name='JobQueue';            Path='jobqueue';            ReadScope='read_job_queues';         WriteScope='manage_job_queues';DeleteScope='manage_job_queues' }
        [pscustomobject]@{ Name='Note';                Path='note';                ReadScope='read_job_notes';          WriteScope='publish_job_notes';DeleteScope='publish_job_notes' }

        # Customers / contacts
        [pscustomobject]@{ Name='CompanyContact';      Path='companycontact';      ReadScope='read_customer_contacts';  WriteScope='manage_customer_contacts';DeleteScope='manage_customer_contacts' }

        # Inventory / assets
        [pscustomobject]@{ Name='Asset';               Path='asset';               ReadScope='read_assets';             WriteScope='manage_assets';   DeleteScope='manage_assets' }
        [pscustomobject]@{ Name='AssetType';           Path='assettype';           ReadScope='read_assets';             WriteScope='manage_assets';   DeleteScope='manage_assets' }
        [pscustomobject]@{ Name='AssetTypeField';      Path='assettypefield';      ReadScope='read_assets';             WriteScope='manage_assets';   DeleteScope='manage_assets' }
        [pscustomobject]@{ Name='Bundle';              Path='bundle';              ReadScope='read_inventory';          WriteScope='manage_inventory';DeleteScope='manage_inventory' }

        # Templates / forms
        [pscustomobject]@{ Name='DocumentTemplate';    Path='documenttemplate';    ReadScope='manage_templates';        WriteScope='manage_templates';DeleteScope='manage_templates' }
        [pscustomobject]@{ Name='EmailTemplate';       Path='emailtemplate';       ReadScope='manage_templates';        WriteScope='manage_templates';DeleteScope='manage_templates' }
        [pscustomobject]@{ Name='Smstemplate';         Path='smstemplate';         ReadScope='manage_templates';        WriteScope='manage_templates';DeleteScope='manage_templates' }
        [pscustomobject]@{ Name='Form';                Path='form';                ReadScope='read_forms';              WriteScope='manage_forms';    DeleteScope='manage_forms' }
        [pscustomobject]@{ Name='FormField';           Path='formfield';           ReadScope='read_forms';              WriteScope='manage_forms';    DeleteScope='manage_forms' }
        [pscustomobject]@{ Name='FormResponse';        Path='formresponse';        ReadScope='read_forms';              WriteScope='manage_forms';    DeleteScope='manage_forms' }

        # Operations reference
        [pscustomobject]@{ Name='Category';            Path='category';            ReadScope='read_job_categories';     WriteScope='manage_job_categories';DeleteScope='manage_job_categories' }
        [pscustomobject]@{ Name='Task';                Path='task';                ReadScope='read_tasks';              WriteScope='manage_tasks';    DeleteScope='manage_tasks' }
        [pscustomobject]@{ Name='TaxRate';             Path='taxrate';             ReadScope='read_tax_rates';          WriteScope='create_tax_rates';DeleteScope='manage_tax_rates' }
        [pscustomobject]@{ Name='Location';            Path='location';            ReadScope='read_locations';          WriteScope='manage_locations';DeleteScope='manage_locations' }
        [pscustomobject]@{ Name='StaffMember';         Path='staffmember';         ReadScope='read_staff';              WriteScope='manage_staff';    DeleteScope='manage_staff' }
        [pscustomobject]@{ Name='StaffMessage';        Path='staffmessage';        ReadScope='read_messages';           WriteScope='publish_messages';DeleteScope='publish_messages' }
        [pscustomobject]@{ Name='Supplier';            Path='supplier';            ReadScope='read_suppliers';          WriteScope='manage_suppliers';DeleteScope='manage_suppliers' }
        [pscustomobject]@{ Name='SecurityRole';        Path='securityrole';        ReadScope='read_security_roles';     WriteScope='read_security_roles';DeleteScope='read_security_roles' }
        [pscustomobject]@{ Name='Badge';               Path='badge';               ReadScope='manage_badges';           WriteScope='manage_badges';   DeleteScope='manage_badges' }
        [pscustomobject]@{ Name='Feedback';            Path='feedback';            ReadScope='read_feedback';           WriteScope='manage_feedback';DeleteScope='manage_feedback' }
        [pscustomobject]@{ Name='KnowledgeArticle';    Path='knowledgearticle';    ReadScope='read_knowledge';          WriteScope='manage_knowledge';DeleteScope='manage_knowledge' }
    )

    return $resources
}

Export-ModuleMember -Function Get-Sm8Registry
