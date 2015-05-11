/*-
 * Copyright (c) 2013 Michael Roe
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

/*
 * xmlcat.c
 * Concatenate together several JUnit XML files
 */

#include <stdio.h>
#include <libxml/xmlreader.h>

static void print_children(xmlNode *node);

static void processNode(xmlTextReaderPtr reader)
{
const xmlChar *name;

  name = xmlTextReaderConstName(reader);
  if (name != NULL)
    printf("%s\n", name);
}

static void print_attributes(xmlAttr *attr)
{
  while (attr)
  {
    if (attr->name)
    {
      printf("%s", attr->name);
      if (attr->children && attr->children->content)
        printf("= %s", attr->children->content);
      printf("\n");
    } 
#if 0
    if (attr->children)
      print_children(attr->children);
#endif
    attr = attr->next;
  }
}

static void print_children(xmlNode *node)
{
  while (node)
  {
    switch(node->type)
    {
      case XML_ELEMENT_NODE:
        printf("%s\n", node->name);
        break;
      case XML_ATTRIBUTE_NODE:
        printf("attribute\n");
        break;
      case XML_TEXT_NODE:
        printf("text\n");
        break;
      default:
        printf("type %d\n", node->type);
        break;
    }

    print_attributes(node->properties);

    if (node->content)
      printf("content = %s\n", node->content);

    node = node->next;
  }
}

int main(int argc, char **argv)
{
char buff[16];
xmlDoc *doc_in;
xmlDoc *doc_out;
xmlNode *root_in;
xmlNode *root_out;
xmlTextReaderPtr reader;
xmlAttr *attr;
xmlNode *children;
int i;
int rc;
int tests = 0;
int errors = 0;
int failures = 0;
int skip = 0;

  doc_out = xmlNewDoc(BAD_CAST "1.0");
  root_out = xmlNewNode(NULL, BAD_CAST "testsuite");
  xmlNewProp(root_out, BAD_CAST "name", BAD_CAST "nosetests");
  xmlDocSetRootElement(doc_out, root_out);

  for (i=1; i<argc; i++)
  {
    doc_in = xmlReadFile(argv[i], NULL, 0);

    if (doc_in == NULL)
    {
      fprintf(stderr, "Failed to open %s\n", argv[i]);
      return -1;
    }
    root_in = xmlDocGetRootElement(doc_in);
#if 0
    printf("%s\n", root_in->name);
#endif
    attr = root_in->properties;
    while (attr)
    {
      if (strcmp(attr->name, "tests") == 0)
      {
        if (attr->children && attr->children->content)
          tests += atoi(attr->children->content);
      }
      else if (strcmp(attr->name, "errors") == 0)
      {
        if (attr->children && attr->children->content)
          errors += atoi(attr->children->content);
      }
      else if (strcmp(attr->name, "failures") == 0)
      {
        if (attr->children && attr->children->content)
          failures += atoi(attr->children->content);
      }
      else if (strcmp(attr->name, "skip") == 0)
      {
        if (attr->children && attr->children->content)
          skip += atoi(attr->children->content);
      }
      attr = attr->next;
    }
    children = root_in->children;
    while (children)
    {
      xmlAddChild(root_out, xmlCopyNode(children, 1));
      children = children->next;
    }
    xmlFreeDoc(doc_in); 
  }

#if 0
  printf("tests = %d\n", tests);
  printf("failures = %d\n", failures);
  printf("errors = %d\n", errors);
  printf("skip = %d\n", skip);
#endif

  sprintf(buff, "%d", tests);
  xmlNewProp(root_out, BAD_CAST "tests", BAD_CAST buff);
  sprintf(buff, "%d", failures);
  xmlNewProp(root_out, BAD_CAST "failures", BAD_CAST buff);
  sprintf(buff, "%d", errors);
  xmlNewProp(root_out, BAD_CAST "errors", BAD_CAST buff);
  sprintf(buff, "%d", skip);
  xmlNewProp(root_out, BAD_CAST "skip", BAD_CAST buff);

  xmlSaveFormatFileEnc("-", doc_out, "UTF-8", 1);

  return 0;
}
