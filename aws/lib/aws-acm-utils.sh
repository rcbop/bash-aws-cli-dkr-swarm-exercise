#!/bin/bash

get_acm_certificate_arn(){
    aws acm list-certificates | jq -r ".CertificateSummaryList[] | select(.DomainName == \"$AWS_CERTIFICATE_DOMAIN\" ) | .CertificateArn"
}