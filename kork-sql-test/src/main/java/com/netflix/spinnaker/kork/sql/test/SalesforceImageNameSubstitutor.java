/*
 * Copyright 2021 Salesforce, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.netflix.spinnaker.kork.sql.test;

import lombok.extern.slf4j.Slf4j;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.utility.ImageNameSubstitutor;

/**
 * Substitute (public) docker image names with an appropriate-for-Salesforce substitute
 *
 * <p>See
 * https://www.testcontainers.org/features/image_name_substitution/#developing-a-custom-function-for-transforming-image-names-on-the-fly
 * for background.
 */
@Slf4j
public class SalesforceImageNameSubstitutor extends ImageNameSubstitutor {

  /** An internal-to-Salesforce mysql docker image */
  private static final DockerImageName SALESFORCE_MYSQL =
      DockerImageName.parse("dva-registry.internal.salesforce.com/dva/sfcd/mysql:24");

  @Override
  public DockerImageName apply(DockerImageName original) {
    log.debug("considering {} for substitution", original);

    // For now, only substitute mysql with an internally-built one since as of
    // 31-oct-21, the public ones have vulnerabilities.  See
    // e.g. https://snyk.io/test/docker/mysql%3A5.7.35 and
    // https://snyk.io/test/docker/mysql%3A5.7.36.
    //
    // If there's also a PrefixingImageNameSubstitutor involved, the name we get
    // has the prefix already bolted on to the beginning.  So, look for mysql at
    // the end, instead of an exact match.
    if (original.getUnversionedPart().endsWith(MySQLContainer.NAME)) {
      log.info("substituting {} for {}", SALESFORCE_MYSQL, original);
      return SALESFORCE_MYSQL;
    }
    return original;
  }

  @Override
  protected String getDescription() {
    return "Substitute public images with internal-to-Salesforce replacements";
  }
}
